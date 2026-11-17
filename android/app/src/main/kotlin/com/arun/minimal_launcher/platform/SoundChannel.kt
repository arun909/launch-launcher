package com.arun.minimal_launcher.platform

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.arun.minimal_launcher.privileged.PrivilegedServiceClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The control center's sound controls: media volume, the ringer mode
 * (normal / vibrate / silent) and Do Not Disturb.
 * Mirrors lib/core/platform/sound_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/sound`
 *   getSound()            -> Map: volume (0..1 of media volume), ringer ("normal" | "vibrate" | "silent"), dnd
 *   setVolume({value})    -> "done"                 value: 0..1 of media volume
 *   setRinger({mode})     -> "done" | "opened"      mode: "normal" | "vibrate" | "silent"
 *   setDnd({on})          -> "done" | "opened"
 * Event channel `com.arun.minimal_launcher/sound/events`: an event (no
 * payload) whenever one of them may have changed; call getSound() again.
 *
 * The ringer mode is set through Shizuku when it's running, as the system's
 * volume panel does: an app's silent also turns on Do Not Disturb (and DND
 * off puts the ringer back to normal), the panel's doesn't.
 *
 * Permissions: without Shizuku, silent mode and DND need Do Not Disturb access, granted
 * through Shizuku when it's running; otherwise its settings page opens
 * ("opened").
 */
class SoundChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val events = EventChannel(messenger, "$CHANNEL/events")
    private val main = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val service = PrivilegedServiceClient.shared(context)
    private val audio = context.getSystemService(AudioManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)

    private var sink: EventChannel.EventSink? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = changed()
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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val filter = IntentFilter().apply {
            addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
            addAction(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
            addAction(VOLUME_CHANGED)
        }
        // System broadcasts only; nothing outside needs to reach it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    override fun onCancel(arguments: Any?) {
        if (sink == null) return
        sink = null
        runCatching { context.unregisterReceiver(receiver) }
    }

    /** Coalesces bursts (a volume drag changes it many times). */
    private val notify = Runnable { sink?.success(null) }

    private fun changed() {
        main.removeCallbacks(notify)
        main.postDelayed(notify, 60)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSound" -> result.success(sound())
            "setVolume" -> {
                val value = call.argument<Double>("value") ?: return result.error("BAD_ARGS", "value is required", null)
                val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val index = Math.round(value.coerceIn(0.0, 1.0) * max).toInt()
                try {
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                    result.success("done")
                } catch (e: SecurityException) {
                    result.error("SOUND_ERROR", e.message, null)
                }
            }
            "setRinger" -> {
                val mode = when (call.argument<String>("mode")) {
                    "normal" -> AudioManager.RINGER_MODE_NORMAL
                    "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                    "silent" -> AudioManager.RINGER_MODE_SILENT
                    else -> return result.error("BAD_ARGS", "mode is required", null)
                }
                inBackground(result) {
                    // Through Shizuku: silent without Do Not Disturb.
                    if (shizukuReady() && runCatching { service.get().setRingerMode(mode) }.getOrElse { "failed" } == null) {
                        return@inBackground "done"
                    }
                    try {
                        audio.ringerMode = mode
                        "done"
                    } catch (_: SecurityException) {
                        // Into or out of silent while DND is on needs DND access.
                        if (!ensurePolicyAccess()) openPolicyAccess()
                        else {
                            audio.ringerMode = mode
                            "done"
                        }
                    }
                }
            }
            "setDnd" -> {
                val on = call.argument<Boolean>("on") ?: return result.error("BAD_ARGS", "on is required", null)
                inBackground(result) {
                    if (!ensurePolicyAccess()) openPolicyAccess()
                    else {
                        notifications.setInterruptionFilter(
                            if (on) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                            else NotificationManager.INTERRUPTION_FILTER_ALL,
                        )
                        "done"
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun sound(): Map<String, Any?> {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return mapOf(
            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max,
            "volumeSteps" to max,
            "ringer" to when (audio.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            },
            "dnd" to (notifications.currentInterruptionFilter.let {
                it != NotificationManager.INTERRUPTION_FILTER_ALL && it != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
            }),
        )
    }

    private fun ensurePolicyAccess(): Boolean {
        if (notifications.isNotificationPolicyAccessGranted) return true
        if (!shizukuReady()) return false
        runCatching { service.get().grantControlAccess(context.packageName) }
        repeat(10) {
            if (notifications.isNotificationPolicyAccessGranted) return true
            Thread.sleep(50)
        }
        return notifications.isNotificationPolicyAccessGranted
    }

    private fun openPolicyAccess(): String {
        try {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: ActivityNotFoundException) {
        }
        return "opened"
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
                main.post { result.error("SOUND_ERROR", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val CHANNEL = "com.arun.minimal_launcher/sound"

        /** Hidden, but sent for every stream's volume change. */
        private const val VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
    }
}
