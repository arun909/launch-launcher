package com.arun.minimal_launcher.platform

import android.app.Activity
import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.MediaStore
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The instant-search widget's native side: the phone's QR scanner, voice
 * input, photo picker, camera and recorder, and the apps that can take a
 * search, a link / UPI payment or an image.
 * Mirrors lib/core/platform/instant_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/instant`
 *   targets({kind: "text" | "link" | "image", data: String?}) -> List<Map> (see [target])
 *   open({target: Map, text: String?, file: String?})        -> Boolean
 *   more({kind: "text" | "image", text, file})               -> Boolean (Android's share sheet)
 *   scan()        -> String? (the code's text; null if cancelled). Errors: SCANNER_DOWNLOADING
 *   listen()      -> String? (what was said; null if cancelled)
 *   pickImage()   -> String? (a private copy's path; null if cancelled)
 *   capture()     -> String? (a photo from our live viewfinder, [CaptureActivity], as a private file's path;
 *                    null if cancelled). Errors: CAMERA_DENIED
 *   openCamera()  -> Boolean
 *   openRecorder()-> Boolean
 *
 * Only one scan / listen / pick runs at a time: a second call while one is
 * open gets BUSY.
 */
class InstantChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val pm: PackageManager = activity.packageManager
    private val main = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    /** The listen / pick / capture call waiting for its activity result. */
    private var pending: Pair<Int, MethodChannel.Result>? = null

    /** Where the camera is writing the photo being taken (see [capture]). */
    private var captureFile: File? = null

    fun register() {
        channel.setMethodCallHandler(this)
        prefetchScanner()
    }

    fun unregister() {
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "targets" -> {
                val kind = call.argument<String>("kind") ?: "text"
                val data = call.argument<String>("data")
                inBackground(result) {
                    when (kind) {
                        "link" -> data?.let { linkTargets(it) } ?: emptyList()
                        "image" -> imageTargets()
                        else -> textTargets()
                    }
                }
            }

            "open" -> {
                @Suppress("UNCHECKED_CAST")
                val target = call.argument<Map<String, Any?>>("target") ?: emptyMap()
                result.success(open(target, call.argument("text"), call.argument("file")))
            }

            "more" -> result.success(more(call.argument("kind"), call.argument("text"), call.argument("file")))

            "scan" -> scan(result)

            "listen" -> forResult(result, REQUEST_LISTEN) {
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
                    .putExtra(RecognizerIntent.EXTRA_PROMPT, "Search for…")
            }

            "pickImage" -> forResult(result, REQUEST_PICK) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
                } else {
                    Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
                }
            }

            "capture" -> capture(result)

            "openCamera" -> result.success(
                start(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            )

            "openRecorder" -> result.success(openRecorder())

            "chrome" -> result.success(chrome(call.argument("action"), call.argument("url")))

            // The full-screen button over browsers (BrowserButtonService).
            "browserButton" -> result.success(BrowserButtonService.isButtonOn(activity))
            "setBrowserButton" -> result.success(BrowserButtonService.setButton(activity, call.argument<Boolean>("on") == true))
            // Hold-to-search over any app (QuickSearchOverlay, in the same service).
            "holdSearch" -> result.success(BrowserButtonService.isHoldSearchOn(activity))
            "setHoldSearch" -> result.success(BrowserButtonService.setHoldSearch(activity, call.argument<Boolean>("on") == true))
            // Which places its bar shows, in order (SearchPlaces); read off the main thread (icons).
            "holdSearchPlaces" -> Thread {
                val all = SearchPlaces.all(activity)
                val shown = SearchPlaces.shown(activity).map { it.id }
                val ordered = shown.mapNotNull { id -> all.firstOrNull { it.id == id } } + all.filter { it.id !in shown }
                val size = (40 * activity.resources.displayMetrics.density).toInt()
                val list = ordered.map {
                    mapOf(
                        "id" to it.id,
                        "label" to it.label,
                        "installed" to (it.pkg != null || it.private),
                        "shown" to (it.id in shown),
                        "icon" to SearchPlaces.iconPng(it, size),
                    )
                }
                activity.runOnUiThread { result.success(list) }
            }.start()
            "setHoldSearchPlaces" -> {
                SearchPlaces.setShown(activity, call.argument<List<String>>("ids") ?: emptyList())
                result.success(true)
            }
            "browserButtonSettings" -> result.success(BrowserButtonService.openSettings(activity))

            else -> result.notImplemented()
        }
    }

    // ---- Who can take it -------------------------------------------------

    /** How an app is handed a search. */
    private enum class Mode { WEB_SEARCH, SEND, URL }

    private class Provider(val pkg: String, val mode: Mode, val template: String? = null, val label: String? = null)

    /**
     * Apps that can search for a text, best first. Each is listed only if
     * installed and able to take it; any other app that handles web searches
     * (a browser) comes after.
     */
    private val textProviders = listOf(
        Provider("com.google.android.googlequicksearchbox", Mode.WEB_SEARCH),
        Provider("com.anthropic.claude", Mode.SEND),
        Provider("com.openai.chatgpt", Mode.SEND),
        Provider("com.google.android.apps.bard", Mode.SEND),
        Provider("ai.perplexity.app.android", Mode.SEND),
        Provider("com.android.chrome", Mode.WEB_SEARCH),
        Provider("com.google.android.youtube", Mode.URL, "https://www.youtube.com/results?search_query=%s"),
        Provider("com.google.android.apps.maps", Mode.URL, "geo:0,0?q=%s"),
        Provider("com.android.vending", Mode.URL, "market://search?q=%s&c=apps", "Play Store"),
        Provider("in.amazon.mShop.android.shopping", Mode.URL, "https://www.amazon.in/s?k=%s"),
        Provider("com.flipkart.android", Mode.URL, "https://www.flipkart.com/search?q=%s"),
        Provider("com.spotify.music", Mode.URL, "spotify:search:%s"),
    )

    private fun textTargets(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()
        for (p in textProviders) {
            val intent = when (p.mode) {
                Mode.WEB_SEARCH -> Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, "a")
                Mode.SEND -> Intent(Intent.ACTION_SEND).setType("text/plain")
                Mode.URL -> Intent(Intent.ACTION_VIEW, Uri.parse(p.template!!.format("a")))
            }.setPackage(p.pkg)
            val info = query(intent).firstOrNull() ?: continue
            out += target(info, p.mode.name, p.template, p.label)
            seen += p.pkg
        }
        for (info in query(Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, "a"))) {
            if (seen.add(info.activityInfo.packageName)) out += target(info, Mode.WEB_SEARCH.name)
        }
        return out
    }

    /** Payment apps known to handle UPI QR codes, in this order; others after. */
    private val upiOrder = listOf(
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp", // BHIM
        "in.amazon.mShop.android.shopping",
        "com.dreamplug.androidapp", // CRED
    )

    /**
     * Apps that open [data] (a link, a UPI payment, a phone number…), for
     * UPI the known payment apps first. Empty if [data] isn't a link any
     * app opens.
     */
    private fun linkTargets(data: String): List<Map<String, Any?>> {
        val uri = Uri.parse(data.trim())
        if (uri.scheme.isNullOrEmpty()) return emptyList()
        val found = query(Intent(Intent.ACTION_VIEW, uri))
            .filter { it.activityInfo.packageName != activity.packageName }
            .distinctBy { it.activityInfo.packageName }
        val ranked = found.sortedBy { info ->
            upiOrder.indexOf(info.activityInfo.packageName).let { if (it < 0) upiOrder.size else it }
        }
        return ranked.map { target(it, "VIEW") }
    }

    /** Apps worth sending an image to: Lens, the assistants, payment apps (they read QR codes). */
    private val imageApps = listOf(
        "com.google.android.googlequicksearchbox", // its Lens entry, see imageTargets
        "com.anthropic.claude",
        "com.openai.chatgpt",
        "com.google.android.apps.bard",
        "ai.perplexity.app.android",
        "com.google.android.apps.nbu.paisa.user",
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp",
    )

    private fun imageTargets(): List<Map<String, Any?>> {
        val all = query(Intent(Intent.ACTION_SEND).setType("image/*"))
        return imageApps.mapNotNull { pkg ->
            val ofApp = all.filter { it.activityInfo.packageName == pkg }
            val info = if (pkg == "com.google.android.googlequicksearchbox") {
                ofApp.firstOrNull { it.activityInfo.name.contains("lens", ignoreCase = true) }
            } else {
                ofApp.firstOrNull()
            } ?: return@mapNotNull null
            target(info, "SEND_IMAGE", label = if (pkg == "com.google.android.googlequicksearchbox") "Lens" else null)
        }
    }

    /** One app that can take it, as Dart gets it back (and hands to [open]). */
    private fun target(info: ResolveInfo, mode: String, template: String? = null, label: String? = null) = mapOf(
        "package" to info.activityInfo.packageName,
        "activity" to info.activityInfo.name,
        "label" to (label ?: info.activityInfo.applicationInfo.loadLabel(pm).toString()),
        "mode" to mode,
        "template" to template,
    )

    // ---- Handing it over -------------------------------------------------

    private fun open(target: Map<String, Any?>, text: String?, file: String?): Boolean {
        val pkg = target["package"] as? String ?: return false
        val activityName = target["activity"] as? String ?: return false
        val query = text?.trim().orEmpty()
        // Nothing typed: just open the app.
        if (query.isEmpty() && file == null) {
            return pm.getLaunchIntentForPackage(pkg)?.let { start(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } ?: false
        }
        val intent = when (target["mode"]) {
            "WEB_SEARCH" -> Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, query)
                .setClassName(pkg, activityName)
            "SEND" -> Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, query)
                .setClassName(pkg, activityName)
            // The search's own URL, so the app picks the activity for it.
            "URL" -> Intent(
                Intent.ACTION_VIEW,
                Uri.parse((target["template"] as String).format(Uri.encode(query))),
            ).setPackage(pkg)
            "VIEW" -> Intent(Intent.ACTION_VIEW, Uri.parse(query)).setClassName(pkg, activityName)
            "SEND_IMAGE" -> imageIntent(file ?: return false)?.setClassName(pkg, activityName) ?: return false
            else -> return false
        }
        return start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Android's own share sheet, for apps not in the list. */
    private fun more(kind: String?, text: String?, file: String?): Boolean {
        val intent = if (kind == "image") {
            imageIntent(file ?: return false) ?: return false
        } else {
            Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text.orEmpty())
        }
        return start(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Shares our private copy of a picked image (see [copyPicked]) through our FileProvider. */
    private fun imageIntent(path: String): Intent? {
        val f = File(path)
        if (!f.exists()) return null
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.instant.files", f)
        return Intent(Intent.ACTION_SEND)
            .setType(activity.contentResolver.getType(uri) ?: "image/*")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .also { it.clipData = ClipData.newRawUri(null, uri) }
    }

    /** The phone's recorder app itself (not its record-and-return screen). */
    private fun openRecorder(): Boolean {
        val pkg = query(Intent(MediaStore.Audio.Media.RECORD_SOUND_ACTION)).firstOrNull()?.activityInfo?.packageName
        val launch = pkg?.let { pm.getLaunchIntentForPackage(it) }
            ?: Intent(MediaStore.Audio.Media.RECORD_SOUND_ACTION)
        return start(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // ---- Chrome widget -----------------------------------------------------

    private val chromePackages = listOf("com.android.chrome", "com.chrome.beta", "com.chrome.dev", "com.chrome.canary")

    private fun chromePackage(): String? = chromePackages.firstOrNull { pm.getLaunchIntentForPackage(it) != null }

    /**
     * Chrome straight into [action]: "incognito" (a new Incognito tab),
     * "search" (its search box), "url" (opens [url]); anything else opens it.
     */
    private fun chrome(action: String?, url: String?): Boolean {
        val pkg = chromePackage() ?: return false
        fun launch() = pm.getLaunchIntentForPackage(pkg)?.let { start(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } ?: false
        return when (action) {
            // Chrome only opens Incognito for its own shortcut (third-party
            // intents are refused), which the home app may start.
            "incognito" -> chromeShortcut(pkg, "incognito") ||
                start(
                    Intent("chromium.shortcut.action.OPEN_NEW_INCOGNITO_TAB")
                        .setPackage(pkg)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                ) ||
                launch()

            "search" -> start(
                Intent(Intent.ACTION_WEB_SEARCH)
                    .setClassName(pkg, "org.chromium.chrome.browser.searchwidget.SearchActivity")
                    .putExtra(SearchManager.QUERY, "")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            ) || launch()

            "url" -> start(
                Intent(Intent.ACTION_VIEW, Uri.parse(url ?: return false))
                    .setPackage(pkg)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )

            else -> launch()
        }
    }

    /** Starts [pkg]'s launcher shortcut whose id contains [idPart]; false if there's none (or we aren't home). */
    private fun chromeShortcut(pkg: String, idPart: String): Boolean = try {
        val apps = activity.getSystemService(LauncherApps::class.java)
        if (apps == null || !apps.hasShortcutHostPermission()) {
            false
        } else {
            val query = LauncherApps.ShortcutQuery()
                .setPackage(pkg)
                .setQueryFlags(
                    LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or
                        LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST or
                        LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED,
                )
            val shortcut = apps.getShortcuts(query, Process.myUserHandle())
                ?.firstOrNull { it.id.contains(idPart, ignoreCase = true) && it.isEnabled }
            if (shortcut == null) {
                false
            } else {
                apps.startShortcut(pkg, shortcut.id, null, null, Process.myUserHandle())
                true
            }
        }
    } catch (_: Exception) {
        false
    }

    // ---- Scanner, voice, picker --------------------------------------------

    /**
     * Google's code scanner, from Play services: its own camera screen, so
     * this app needs no camera permission. Its module is downloaded once; if
     * it isn't there yet, this asks for it and reports SCANNER_DOWNLOADING.
     */
    private fun scan(result: MethodChannel.Result) {
        val scanner = GmsBarcodeScanning.getClient(activity)
        scanner.startScan()
            .addOnSuccessListener { result.success(it.rawValue ?: it.displayValue) }
            .addOnCanceledListener { result.success(null) }
            .addOnFailureListener { e ->
                if (e is MlKitException && e.errorCode == MlKitException.UNAVAILABLE) {
                    prefetchScanner()
                    result.error("SCANNER_DOWNLOADING", "The scanner is being downloaded", null)
                } else {
                    result.error("SCAN_FAILED", e.message, null)
                }
            }
    }

    /** Has Play services download the scanner now, so the first scan is instant. */
    private fun prefetchScanner() {
        try {
            val scanner = GmsBarcodeScanning.getClient(activity)
            val modules = ModuleInstall.getClient(activity)
            modules.areModulesAvailable(scanner).addOnSuccessListener {
                if (!it.areModulesAvailable()) {
                    modules.installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
                }
            }
        } catch (_: Exception) {
            // No Play services: scan() reports it when used.
        }
    }

    /**
     * Our live viewfinder ([CaptureActivity]): one tap takes the photo into
     * our private folder and comes straight back. Only the latest image is kept.
     */
    private fun capture(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "Already open", null)
            return
        }
        val out = try {
            freshFile("jpg")
        } catch (e: Exception) {
            result.error("NATIVE_ERROR", e.message, null)
            return
        }
        captureFile = out
        forResult(result, REQUEST_CAPTURE) {
            Intent(activity, CaptureActivity::class.java).putExtra(CaptureActivity.EXTRA_OUTPUT, out.absolutePath)
        }
        @Suppress("DEPRECATION")
        activity.overridePendingTransition(android.R.anim.fade_in, 0)
        if (pending == null) captureFile = null
    }

    private fun forResult(result: MethodChannel.Result, code: Int, intent: () -> Intent) {
        if (pending != null) {
            result.error("BUSY", "Already open", null)
            return
        }
        try {
            pending = code to result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent(), code)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("UNAVAILABLE", "No app on this phone does that", null)
        }
    }

    /** From MainActivity; true if it was one of ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val (code, result) = pending ?: return false
        if (code != requestCode) return false
        pending = null
        if (requestCode == REQUEST_CAPTURE) {
            // The photo is in the file we gave it; it returns no data.
            val file = captureFile
            captureFile = null
            if (resultCode == CaptureActivity.RESULT_DENIED) {
                file?.delete()
                result.error("CAMERA_DENIED", "Camera permission denied", null)
                return true
            }
            val taken = resultCode == Activity.RESULT_OK && file != null && file.length() > 0
            if (!taken) file?.delete()
            result.success(if (taken) file!!.absolutePath else null)
            return true
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        when (requestCode) {
            REQUEST_LISTEN -> result.success(
                data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            )
            REQUEST_PICK -> {
                val uri = data.data
                if (uri == null) result.success(null) else inBackground(result) { copyPicked(uri) }
            }
        }
        return true
    }

    /**
     * A private copy of the picked image, so it can be handed to any app
     * through our FileProvider (a picker's grant isn't ours to pass on).
     * Only the latest is kept.
     */
    private fun copyPicked(uri: Uri): String {
        val ext = when (activity.contentResolver.getType(uri)) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/heic", "image/heif" -> "heic"
            else -> "jpg"
        }
        val out = freshFile(ext)
        activity.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Couldn't read the image" }
            out.outputStream().use { input.copyTo(it) }
        }
        return out.absolutePath
    }

    // ---- Helpers -----------------------------------------------------------

    /** A new file in our shared-through-FileProvider folder, the older ones deleted. */
    private fun freshFile(ext: String): File {
        val dir = File(activity.cacheDir, "instant").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        return File(dir, "image-${System.currentTimeMillis()}.$ext")
    }

    private fun query(intent: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
    }

    companion object {
        const val CHANNEL = "com.arun.minimal_launcher/instant"
        private const val REQUEST_LISTEN = 0x4e01
        private const val REQUEST_PICK = 0x4e02
        private const val REQUEST_CAPTURE = 0x4e03
    }
}
