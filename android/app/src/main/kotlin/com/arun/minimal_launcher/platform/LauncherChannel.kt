package com.arun.minimal_launcher.platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
 *     getAppIcons({ids: List<String>, sizePx})   -> Map<String, ByteArray> (PNG)
 *     launchApp({id})                            -> Boolean
 *     openAppInfo({packageName})                 -> null
 *     openHomeSettings()                         -> null  (system "default home app" picker)
 *     isDefaultHome()                            -> Boolean (this app is the current home screen)
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
    private val worker: ExecutorService = Executors.newFixedThreadPool(2)

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
                inBackground(result) { apps.loadIcons(ids, size) }
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

            "openHomeSettings" -> {
                startSafely(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }

            "isDefaultHome" -> result.success(isDefaultHome(context))

            else -> result.notImplemented()
        }
    }

    private fun startSafely(intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
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
    }
}
