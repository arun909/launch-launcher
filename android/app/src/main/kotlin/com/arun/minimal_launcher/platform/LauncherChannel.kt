package com.arun.minimal_launcher.platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import com.arun.minimal_launcher.platform.icons.IconStyle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The single Dart <-> Android bridge for launcher features.
 * Mirrors lib/core/platform/launcher_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/launcher`
 *   Dart -> Android:
 *     getInstalledApps()                         -> List<Map>   (see InstalledAppsSource)
 *     getAppIcons({ids: List<String>, sizePx, cornerRadius: Int? (% of size; null = phone's mask),
 *                  style: Map (see icons/IconStyle), overrides: Map<id, "original" | "<pack>:<name>">})
 *                                                -> Map<String, ByteArray> (PNG)
 *     getPackIcons({refs: List<"<pack>:<name>">, sizePx, cornerRadius, style, appId?})
 *                                                -> Map<String, ByteArray> (PNG; for the icon picker)
 *     getPackIconNames({pack})                   -> List<String> (sorted)
 *     getPackIconsForApp({id})                   -> Map<pack, icon name> (each bundled pack's pick)
 *     launchApp({id})                            -> Boolean
 *     openAppInfo({packageName})                 -> null
 *     uninstallApp({packageName})                -> Boolean (system uninstall dialog opened)
 *     openHomeSettings()                         -> null  (system "default home app" picker)
 *     isDefaultHome()                            -> Boolean (this app is the current home screen)
 *     openSystemWallpapers()                     -> Boolean (the phone's own wallpaper settings,
 *                                                            e.g. vivo's Themes; else the chooser)
 *     expandNotifications()                      -> Boolean (pull down the notification shade)
 *     expandQuickSettings()                      -> Boolean (pull down quick settings)
 *   Android -> Dart:
 *     onHomePressed()                            Home pressed while launcher is in front
 *
 * Event channel `com.arun.minimal_launcher/package_events`
 *     see PackageEventsStreamHandler
 *
 * Adding a new native feature (battery stats, accessibility, ...): prefer a new
 * class + its own channel registered in MainActivity, rather than growing this one.
 */
class LauncherChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val apps = InstalledAppsSource(context)
    private val mainHandler = Handler(Looper.getMainLooper())

    // PackageManager queries and PNG encoding are slow; never run them on the UI thread.
    // AppsController renders two icon batches at once; the third thread keeps
    // settings previews and other calls from queueing behind them.
    private val worker: ExecutorService = Executors.newFixedThreadPool(3)

    fun register() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(PackageEventsStreamHandler(context))
    }

    fun unregister() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        worker.shutdownNow()
    }

    fun notifyHomePressed() {
        methodChannel.invokeMethod("onHomePressed", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> inBackground(result) { apps.queryLaunchableApps() }

            "getAppIcons" -> {
                val ids = call.argument<List<String>>("ids") ?: emptyList()
                val size = call.argument<Int>("sizePx") ?: DEFAULT_ICON_PX
                val cornerRadius = call.argument<Int>("cornerRadius")
                val style = IconStyle.fromMap(call.argument<Map<String, Any?>>("style"))
                val overrides = call.argument<Map<String, String>>("overrides") ?: emptyMap()
                inBackground(result) { apps.loadIcons(ids, size, cornerRadius, style, overrides) }
            }

            "getPackIcons" -> {
                val refs = call.argument<List<String>>("refs") ?: emptyList()
                val size = call.argument<Int>("sizePx") ?: DEFAULT_ICON_PX
                val cornerRadius = call.argument<Int>("cornerRadius")
                val style = IconStyle.fromMap(call.argument<Map<String, Any?>>("style"))
                val appId = call.argument<String>("appId")
                inBackground(result) { apps.loadPackIcons(refs, size, cornerRadius, style, appId) }
            }

            "getPackIconNames" -> {
                val pack = call.argument<String>("pack") ?: ""
                inBackground(result) { apps.packIconNames(pack) }
            }

            "getPackIconsForApp" -> {
                val id = call.argument<String>("id") ?: ""
                inBackground(result) { apps.packIconsFor(id) }
            }

            "launchApp" -> {
                val id = call.argument<String>("id")
                val intent = id?.let { apps.launchIntentFor(it) }
                result.success(intent != null && startSafely(intent))
            }

            "openAppInfo" -> {
                val pkg = call.argument<String>("packageName")
                if (pkg != null) {
                    startSafely(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
                result.success(null)
            }

            "uninstallApp" -> {
                val pkg = call.argument<String>("packageName")
                // Android's own confirm dialog; the user decides there.
                result.success(
                    pkg != null && startSafely(
                        Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                )
            }

            "openHomeSettings" -> {
                startSafely(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }

            "isDefaultHome" -> result.success(isDefaultHome(context))

            // Only opens the OS's own screen; the user sets the wallpaper there.
            "openSystemWallpapers" -> result.success(openSystemWallpapers())

            // The phone's default clock app (its alarms), whoever makes it.
            "openClock" -> result.success(
                startSafely(Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            )

            "expandNotifications" -> result.success(expandStatusBar("expandNotificationsPanel"))

            "expandQuickSettings" -> result.success(expandStatusBar("expandSettingsPanel"))

            "setHiddenNotifications" -> {
                HiddenNotifications.set(
                    context,
                    call.argument<Boolean>("block") ?: false,
                    call.argument<List<String>>("packages").orEmpty(),
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * The phone's own wallpaper settings, where albums, live wallpapers and
     * the rest all are; else the system app among those that set wallpapers
     * (not Photos, Gallery...); else the chooser of all of them.
     *
     * On vivo phones that's Settings' "Choose wallpaper from" page (its
     * Themes entry is the full wallpaper gallery). vivo's gallery can't be
     * opened directly: it closes itself at once unless a system app opened
     * it (vivo Themes' SecureUtils.isSafeIntent), and this launcher isn't one.
     */
    private fun openSystemWallpapers(): Boolean {
        val pm = context.packageManager
        val set = Intent(Intent.ACTION_SET_WALLPAPER)
        if (Intent(VIVO_WALLPAPERS).resolveActivity(pm) != null) {
            val settings = Intent().setClassName("com.android.settings", VIVO_SETTINGS_WALLPAPER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (settings.resolveActivity(pm) != null && startSafely(settings)) return true
        }
        val system = pm.queryIntentActivities(set, 0).firstOrNull {
            (it.activityInfo.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
        }
        if (system != null) {
            val own = Intent(set).setClassName(system.activityInfo.packageName, system.activityInfo.name)
            if (startSafely(own.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) return true
        }
        return startSafely(Intent.createChooser(set, "Set wallpaper with").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun startSafely(intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    /**
     * Calls a StatusBarManager panel method. They aren't in the public SDK,
     * but are allowed for apps (launchers commonly use them) and need only
     * the install-time EXPAND_STATUS_BAR permission.
     */
    private fun expandStatusBar(method: String): Boolean = try {
        val statusBar = context.getSystemService("statusbar") ?: error("no status bar service")
        statusBar.javaClass.getMethod(method).invoke(statusBar)
        true
    } catch (_: Exception) {
        false
    }

    /** Runs [work] on the worker pool and replies on the main thread (required by Flutter). */
    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
    }

    companion object {
        /** True if Android currently uses this app as the home screen. */
        fun isDefaultHome(context: Context): Boolean {
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.resolveActivity(
                    home, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
            }
            return info?.activityInfo?.packageName == context.packageName
        }

        const val METHOD_CHANNEL = "com.arun.minimal_launcher/launcher"
        const val EVENT_CHANNEL = "com.arun.minimal_launcher/package_events"
        private const val DEFAULT_ICON_PX = 192

        /** vivo Themes' wallpaper gallery; only checked for, see [openSystemWallpapers]. */
        private const val VIVO_WALLPAPERS = "com.vivo.action.theme.setting.wallpaper"
        private const val VIVO_SETTINGS_WALLPAPER = "com.android.settings.wallpaper.WallpaperSuggestionActivity"
    }
}
