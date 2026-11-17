package com.arun.minimal_launcher.platform

import android.Manifest
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.arun.minimal_launcher.privileged.PrivilegedServiceClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.lsposed.hiddenapibypass.HiddenApiBypass
import rikka.shizuku.Shizuku
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The control center's display controls: brightness, auto brightness,
 * night mode (the warm night light; vivo's "eye protection"), extra dim and
 * the dark / light theme.
 * Mirrors lib/core/platform/controls_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/controls`
 *   getDisplay()                 -> Map: brightness (0..1 of the setting), autoBrightness,
 *                                   nightLight, extraDim, extraDimAvailable, darkTheme
 *   setBrightness({value})       -> "done" | "opened"   value: 0..1 of the setting
 *   setAutoBrightness({on})      -> "done" | "opened"
 *   setNightLight({on})          -> "done" | "opened"
 *   setExtraDim({on})            -> "done" | "opened"
 *   setDarkTheme({on})           -> "done" | "opened"
 * Event channel `com.arun.minimal_launcher/controls/events`: an event (no
 * payload) whenever one of them may have changed; call getDisplay() again.
 *
 * Permissions: brightness needs "Modify system settings"; night light and
 * extra dim WRITE_SECURE_SETTINGS (adb / Shizuku only); the theme needs
 * shell rights, so goes through Shizuku. Missing ones are granted through Shizuku when
 * it's running; otherwise the matching settings page opens ("opened"), where
 * the user can change it by hand.
 */
class ControlsChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val events = EventChannel(messenger, "$CHANNEL/events")
    private val main = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val service = PrivilegedServiceClient.shared(context)
    private val resolver = context.contentResolver

    private var sink: EventChannel.EventSink? = null
    private var lastNight: Boolean? = null

    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) = changed()
    }

    fun register() {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun unregister() {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        onCancel(null)
        worker.shutdown()
    }

    /** The launcher's activity handles uiMode changes itself: it forwards them here. */
    fun onConfigurationChanged(config: Configuration) {
        val night = config.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        if (night != lastNight) {
            lastNight = night
            changed()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        for (uri in listOf(
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS_MODE),
            Settings.Secure.getUriFor(EXTRA_DIM),
            Settings.Secure.getUriFor(NIGHT_LIGHT),
        )) resolver.registerContentObserver(uri, false, observer)
    }

    override fun onCancel(arguments: Any?) {
        if (sink == null) return
        sink = null
        resolver.unregisterContentObserver(observer)
    }

    /** Coalesces bursts (a brightness drag writes dozens of times). */
    private val notify = Runnable { sink?.success(null) }

    private fun changed() {
        main.removeCallbacks(notify)
        main.postDelayed(notify, 60)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDisplay" -> result.success(display())
            "setBrightness" -> {
                val value = call.argument<Double>("value") ?: return result.error("BAD_ARGS", "value is required", null)
                val level = (value.coerceIn(0.0, 1.0) * BRIGHTNESS_MAX).toInt().coerceIn(1, BRIGHTNESS_MAX.toInt())
                // Fast path while dragging: no worker hop once allowed.
                if (Settings.System.canWrite(context)) {
                    putBrightness(level)
                    result.success("done")
                } else {
                    inBackground(result) {
                        if (!ensureWriteSettings()) openWriteSettings() else putBrightness(level).let { "done" }
                    }
                }
            }
            "setAutoBrightness" -> {
                val on = call.argument<Boolean>("on") ?: return result.error("BAD_ARGS", "on is required", null)
                inBackground(result) {
                    if (!ensureWriteSettings()) openWriteSettings()
                    else {
                        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, if (on) 1 else 0)
                        "done"
                    }
                }
            }
            "setExtraDim", "setNightLight" -> {
                val on = call.argument<Boolean>("on") ?: return result.error("BAD_ARGS", "on is required", null)
                val dim = call.method == "setExtraDim"
                inBackground(result) {
                    if (!ensureWriteSecureSettings()) {
                        if (dim) open(Intent(ACTION_EXTRA_DIM_SETTINGS), Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        else open(Intent(Settings.ACTION_NIGHT_DISPLAY_SETTINGS), Intent(Settings.ACTION_DISPLAY_SETTINGS))
                        "opened"
                    } else {
                        Settings.Secure.putInt(resolver, if (dim) EXTRA_DIM else NIGHT_LIGHT, if (on) 1 else 0)
                        if (dim) lastExtraDim = on else lastNightLight = on
                        "done"
                    }
                }
            }
            "setDarkTheme" -> {
                val on = call.argument<Boolean>("on") ?: return result.error("BAD_ARGS", "on is required", null)
                inBackground(result) {
                    if (!shizukuReady()) {
                        open(Intent(Settings.ACTION_DISPLAY_SETTINGS))
                        "opened"
                    } else {
                        service.get().setNightMode(on)?.let { error(it) }
                        "done"
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun display(): Map<String, Any?> = mapOf(
        "brightness" to Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 128) / BRIGHTNESS_MAX,
        "autoBrightness" to (Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, 0) == 1),
        "nightLight" to colorDisplayFlag("isNightDisplayActivated", NIGHT_LIGHT, lastNightLight),
        "extraDim" to colorDisplayFlag("isReduceBrightColorsActivated", EXTRA_DIM, lastExtraDim),
        "darkTheme" to darkThemeOn(),
        // Android 12+ has extra dim; some phones leave it out.
        "extraDimAvailable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S),
    )

    /**
     * Night light's and extra dim's settings can't be read by apps since
     * Android 12 (hidden Secure keys are system-only), so they're asked of
     * the colour-display service ([getter]), which keeps them. Last resort:
     * what we last wrote.
     */
    private fun colorDisplayFlag(getter: String, key: String, last: Boolean): Boolean {
        runCatching {
            val manager = context.getSystemService("color_display") ?: error("no color_display")
            return HiddenApiBypass.invoke(manager.javaClass, manager, getter) as Boolean
        }
        return runCatching { Settings.Secure.getInt(resolver, key, 0) == 1 }.getOrDefault(last)
    }

    /** What we last set night light and extra dim to (see [colorDisplayFlag]). */
    private var lastExtraDim = false
    private var lastNightLight = false

    /**
     * The phone's own dark theme (UiModeManager's: the Secure setting is
     * system-only to read, like extra dim's).
     */
    private fun darkThemeOn(): Boolean {
        when (context.getSystemService(UiModeManager::class.java).nightMode) {
            UiModeManager.MODE_NIGHT_YES -> return true
            UiModeManager.MODE_NIGHT_NO -> return false
        }
        // Auto / scheduled: whatever is showing now.
        val ui = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return ui == Configuration.UI_MODE_NIGHT_YES
    }

    private fun putBrightness(level: Int) {
        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, level)
    }

    private fun ensureWriteSettings(): Boolean {
        if (Settings.System.canWrite(context)) return true
        grantThroughShizuku()
        return Settings.System.canWrite(context)
    }

    private fun ensureWriteSecureSettings(): Boolean {
        if (hasWriteSecure()) return true
        grantThroughShizuku()
        return hasWriteSecure()
    }

    private fun hasWriteSecure() =
        context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun grantThroughShizuku() {
        if (!shizukuReady()) return
        runCatching { service.get().grantControlAccess(context.packageName) }
        // App ops and grants reach the permission checks a moment later.
        repeat(10) {
            if (Settings.System.canWrite(context) && hasWriteSecure()) return
            Thread.sleep(50)
        }
    }

    private fun openWriteSettings(): String {
        open(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}")))
        return "opened"
    }

    private fun open(vararg intents: Intent): Boolean = intents.any { intent ->
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun shizukuReady(): Boolean = try {
        Shizuku.pingBinder() && !Shizuku.isPreV11() &&
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) {
        false
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("CONTROLS_ERROR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val CHANNEL = "com.arun.minimal_launcher/controls"

        private const val BRIGHTNESS_MAX = 255.0
        private const val EXTRA_DIM = "reduce_bright_colors_activated"
        private const val NIGHT_LIGHT = "night_display_activated"
        private const val ACTION_EXTRA_DIM_SETTINGS = "android.settings.REDUCE_BRIGHT_COLORS_SETTINGS"
    }
}
