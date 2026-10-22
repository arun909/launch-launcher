package com.arun.minimal_launcher.platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import com.arun.minimal_launcher.privileged.PrivilegedServiceClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bridge for disabling / re-enabling system apps through Shizuku.
 * Mirrors lib/core/platform/system_apps_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/system_apps`
 *   getShizukuStatus()                     -> "notInstalled" | "notRunning" | "unsupported"
 *                                             | "permissionNeeded" | "ready"
 *   requestShizukuPermission()             -> Boolean (granted)
 *   openShizuku()                          -> Boolean (opened Shizuku, or its Play Store page)
 *   listSystemApps()                       -> List<Map> (see SystemAppsSource)
 *   setAppEnabled({packageName, enabled})  -> null, or throws PlatformException
 *
 * Safety: besides the app-level risk tiers in Dart, this side refuses
 * [HARD_BLOCKED] packages, any current default-role holder, and non-system
 * apps, so a Dart bug can't disable something critical.
 */
class SystemAppsChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val source = SystemAppsSource(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val service = PrivilegedServiceClient(context.packageName, appVersionCode())
    private var pendingPermission: MethodChannel.Result? = null

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        if (code == PERMISSION_REQUEST_CODE) {
            pendingPermission?.success(grant == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    fun register() {
        channel.setMethodCallHandler(this)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    fun unregister() {
        channel.setMethodCallHandler(null)
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        pendingPermission?.success(false)
        pendingPermission = null
        worker.execute { service.release() }
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getShizukuStatus" -> result.success(shizukuStatus())

            "requestShizukuPermission" -> requestPermission(result)

            "openShizuku" -> result.success(openShizuku())

            "listSystemApps" -> inBackground(result) { source.listSystemApps(ICON_PX) }

            "setAppEnabled" -> {
                val pkg = call.argument<String>("packageName")
                val enabled = call.argument<Boolean>("enabled")
                if (pkg == null || enabled == null) {
                    result.error("BAD_ARGS", "packageName and enabled are required", null)
                    return
                }
                inBackground(result) { setAppEnabled(pkg, enabled) }
            }

            else -> result.notImplemented()
        }
    }

    private fun shizukuStatus(): String {
        if (!Shizuku.pingBinder()) {
            return if (isInstalled(SHIZUKU_PACKAGE)) "notRunning" else "notInstalled"
        }
        if (Shizuku.isPreV11()) return "unsupported"
        return if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) "ready"
        else "permissionNeeded"
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (!Shizuku.pingBinder() || Shizuku.isPreV11()) {
            result.success(false)
            return
        }
        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermission?.success(false) // supersede an older request
        pendingPermission = result
        Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
    }

    private fun setAppEnabled(pkg: String, enabled: Boolean): Any? {
        // Re-enabling is always allowed: it only ever restores the default state.
        if (!enabled) {
            if (pkg in HARD_BLOCKED || pkg == context.packageName) {
                throw IllegalArgumentException("$pkg is essential and can't be disabled")
            }
            source.defaultRoleHolders()[pkg]?.let { role ->
                throw IllegalArgumentException("$pkg is your $role; change the default first")
            }
            if (!source.isSystemApp(pkg)) {
                throw IllegalArgumentException("$pkg isn't a system app; uninstall it normally instead")
            }
        }
        if (shizukuStatus() != "ready") throw IllegalStateException("Shizuku isn't ready")

        val userId = Process.myUid() / PER_USER_UID_RANGE
        val error = service.get().setPackageEnabled(pkg, enabled, userId)
        if (error != null) throw IllegalStateException(error)
        return null
    }

    /**
     * Opens Shizuku if installed, otherwise its Google Play page. Play is
     * targeted explicitly: on vivo/iQOO, a plain market:// link opens
     * V-Appstore, which doesn't carry Shizuku.
     */
    private fun openShizuku(): Boolean {
        val candidates = listOfNotNull(
            context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE),
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$SHIZUKU_PACKAGE"))
                .setPackage(PLAY_STORE_PACKAGE),
            Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$SHIZUKU_PACKAGE")),
        )
        return candidates.any { intent ->
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun appVersionCode(): Int {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return info.longVersionCode.toInt()
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SYSTEM_APPS_ERROR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val CHANNEL = "com.arun.minimal_launcher/system_apps"
        private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
        private const val PLAY_STORE_PACKAGE = "com.android.vending"
        private const val PERMISSION_REQUEST_CODE = 4711
        private const val PER_USER_UID_RANGE = 100_000
        private const val ICON_PX = 128

        /** Never disabled, whatever the UI asks. */
        private val HARD_BLOCKED = setOf(
            "android",
            "com.android.systemui",
            "com.android.settings",
            "com.android.phone",
            "com.android.vending",
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.bbk.lockscreen3",
            "com.vivo.imanager",
            "com.bbk.theme",
            "com.vivo.simplelauncher",
            SHIZUKU_PACKAGE,
        )
    }
}
