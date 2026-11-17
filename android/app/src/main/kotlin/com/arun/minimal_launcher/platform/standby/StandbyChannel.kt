package com.arun.minimal_launcher.platform.standby

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The standby clock's bridge. Registered both on the home screen's engine
 * (settings: on/off, "Show now") and on the clock's own engine
 * ([StandbyEngine]: next alarm, closing on a tap).
 * Mirrors lib/core/platform/standby_platform.dart.
 *
 * Method channel `com.arun.minimal_launcher/standby`
 *   Dart -> Android:
 *     status()                  -> Map {nextAlarm: Long?}
 *     listen(Boolean)           -> null  (push onStatus on every change while true)
 *     isEnabled()               -> Boolean
 *     setEnabled(Boolean)       -> null  (show the clock on the lock screen when sideways)
 *     isKeepOn() / setKeepOn(Boolean)  the clock keeps the screen on while up
 *     canOpenFromLock()         -> Boolean (full-screen notifications allowed)
 *     openPermission()          -> null  (where to allow them)
 *     isOnRest() / setOnRest(Boolean)  also open when locked lying still
 *     showNow()                 -> null  (open the clock now, as a preview)
 *     dismiss()                 -> null  (close the clock; ask to unlock if locked)
 *     hasMediaAccess()          -> Boolean (notification access, to read what's playing)
 *     openMediaAccess()         -> null  (where to allow it)
 *     listenMedia(Boolean)      -> null  (push onMedia on every change while true)
 *     media()                   -> Map?  (what's playing, see [NowPlaying.current]; null if nothing)
 *     mediaCommand({command, positionMs?}) -> Boolean (play/pause/toggle/next/previous/seek)
 *     volume()                  -> Map {current, max} (the shown song's volume, or the phone's music volume)
 *     setVolume(Int)            -> Boolean (quietly: no system volume panel)
 *     hasAudioPermission()      -> Boolean (RECORD_AUDIO, which the beat pulse needs)
 *     requestAudioPermission()  -> null  (Android's dialog; from the launcher only)
 *     listenBeats(Boolean)      -> Boolean (push onBeat while true; false if unavailable)
 *     listenSpectrum(Boolean)   -> Boolean (push onSpectrum while true, the phone's output or a
 *                                 connected laptop's; false if the phone's own is unavailable)
 *   Android -> Dart:
 *     onStatus(Map)             same map as status()
 *     onMedia(Map?)             same map as media(); `art` only when the track changed
 *     onBeat(Map)               {beat: true, band: 0 bass/1 mids/2 treble, strength: 0-1}, on each hit
 *     onSpectrum(Map)           {bands: List<Double> (10, 0-1), left: 0-1, right: 0-1}, each reading
 */
class StandbyChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    /** The launcher's activity, to ask for permissions from (null in the clock's engine). */
    private val activity: android.app.Activity? = null,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private var listening = false
    private val nowPlaying = NowPlaying(
        context,
        // The launcher's engine feeds the home screen's music widget.
        onlySinceLock = activity == null,
        onLevels = {
            remoteLevelsAt = SystemClock.uptimeMillis()
            methodChannel.invokeMethod("onSpectrum", it)
        },
    ) { methodChannel.invokeMethod("onMedia", it) }

    /** When the laptop last sent levels: the phone's own (silent) readings give way meanwhile. */
    private var remoteLevelsAt = 0L
    // Called on the main thread.
    private val beats = BeatVisualizer(context) { methodChannel.invokeMethod("onBeat", it) }

    private val spectrum = SpectrumVisualizer(context) {
        if (SystemClock.uptimeMillis() - remoteLevelsAt > REMOTE_LEVELS_HOLD_MS) methodChannel.invokeMethod("onSpectrum", it)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            methodChannel.invokeMethod("onStatus", status())
        }
    }

    fun register() = methodChannel.setMethodCallHandler(this)

    fun unregister() {
        setListening(false)
        nowPlaying.listenLevels(false)
        nowPlaying.stop()
        beats.stop()
        spectrum.stop()
        methodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "listen" -> {
                setListening(call.arguments == true)
                result.success(null)
            }
            "isEnabled" -> result.success(StandbyMonitor.enabled)
            "setEnabled" -> {
                StandbyMonitor.setEnabled(call.arguments == true)
                result.success(null)
            }
            "isOnRest" -> result.success(StandbyMonitor.onRest)
            "setOnRest" -> {
                StandbyMonitor.onRest = call.arguments == true
                result.success(null)
            }
            "isKeepOn" -> result.success(StandbyMonitor.keepOn)
            "setKeepOn" -> {
                StandbyMonitor.keepOn = call.arguments == true
                result.success(null)
            }
            "canOpenFromLock" -> result.success(StandbyLauncher.canUseFullScreen(context))
            "openPermission" -> {
                StandbyLauncher.openSettings(context)
                result.success(null)
            }
            "showNow" -> {
                context.startActivity(
                    Intent(context, StandbyActivity::class.java)
                        .putExtra(StandbyActivity.EXTRA_PREVIEW, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "dismiss" -> {
                StandbyActivity.dismissCurrent()
                result.success(null)
            }
            "hasAudioPermission" -> result.success(BeatVisualizer.hasPermission(context))
            "requestAudioPermission" -> {
                requestAudioPermission()
                result.success(null)
            }
            "listenBeats" -> result.success(
                if (call.arguments == true) beats.start() else {
                    beats.stop()
                    false
                },
            )
            // The phone's own output, and a connected laptop's (through Phone Link).
            "listenSpectrum" -> {
                val on = call.arguments == true
                nowPlaying.listenLevels(on)
                result.success(
                    if (on) spectrum.start() else {
                        spectrum.stop()
                        false
                    },
                )
            }
            "hasMediaAccess" -> result.success(NowPlaying.hasAccess(context))
            "openMediaAccess" -> {
                NowPlaying.openAccessSettings(context)
                result.success(null)
            }
            "listenMedia" -> {
                if (call.arguments == true) nowPlaying.start() else nowPlaying.stop()
                result.success(null)
            }
            "media" -> result.success(nowPlaying.current())
            "volume" -> result.success(nowPlaying.volume())
            "setVolume" -> result.success(nowPlaying.setVolume((call.arguments as? Number)?.toInt() ?: 0))
            "mediaCommand" -> result.success(
                nowPlaying.command(
                    call.argument<String>("command") ?: "",
                    call.argument<Number>("positionMs")?.toLong(),
                )
            )
            else -> result.notImplemented()
        }
    }

    /**
     * Android's dialog; once it was refused for good (it no longer shows),
     * this app's settings page, where it can still be allowed.
     */
    private fun requestAudioPermission() {
        val a = activity ?: return
        val prefs = context.getSharedPreferences("standby", Context.MODE_PRIVATE)
        val askedBefore = prefs.getBoolean(KEY_AUDIO_ASKED, false)
        val dialogWouldShow = a.shouldShowRequestPermissionRationale(android.Manifest.permission.RECORD_AUDIO)
        if (askedBefore && !dialogWouldShow) {
            a.startActivity(
                Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(android.net.Uri.fromParts("package", context.packageName, null)),
            )
            return
        }
        prefs.edit().putBoolean(KEY_AUDIO_ASKED, true).apply()
        a.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), AUDIO_REQUEST)
    }

    private fun setListening(on: Boolean) {
        if (on == listening) return
        listening = on
        if (on) {
            val filter = IntentFilter(AlarmManager.ACTION_NEXT_ALARM_CLOCK_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
        } else {
            runCatching { context.unregisterReceiver(receiver) }
        }
    }

    private fun status(): Map<String, Any?> = mapOf(
        "nextAlarm" to (context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.nextAlarmClock?.triggerTime,
    )

    companion object {
        const val METHOD_CHANNEL = "com.arun.minimal_launcher/standby"
        private const val AUDIO_REQUEST = 4711
        private const val KEY_AUDIO_ASKED = "audioPermissionAsked"
        private const val REMOTE_LEVELS_HOLD_MS = 400L
    }
}
