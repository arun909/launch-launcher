package com.arun.minimal_launcher.platform

import android.app.Activity
import android.content.pm.ActivityInfo
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.OrientationEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Stops the launcher rotating on every small tilt. The activity stays locked to
 * its current orientation; when the phone is held in another orientation for a
 * moment, Dart is told to offer a rotate button, and the screen turns only when
 * it's tapped. Only this activity's own orientation is touched (and only
 * Android's auto-rotate setting is read), so nothing about the phone changes.
 * Mirrors lib/core/platform/rotation_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/rotation`
 *   Dart -> Android:
 *     rotate()                   -> null  (turn to the suggested orientation)
 *   Android -> Dart:
 *     onSuggestion(Boolean)      true: phone is held in another orientation;
 *                                false: suggestion no longer applies
 */
class RotationChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val handler = Handler(Looper.getMainLooper())

    /** What the phone is physically held as, once it has settled there. */
    private var held = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    private var pending = held
    private var suggesting = false

    private val settle = Runnable {
        held = pending
        updateSuggestion()
    }

    private val listener = object : OrientationEventListener(activity, SensorManager.SENSOR_DELAY_UI) {
        override fun onOrientationChanged(degrees: Int) {
            val next = orientationFor(degrees) ?: return
            if (next == pending) return
            pending = next
            handler.removeCallbacks(settle)
            handler.postDelayed(settle, SETTLE_MS)
        }
    }

    fun register() {
        methodChannel.setMethodCallHandler(this)
        lockTo(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
    }

    fun unregister() {
        stop()
        methodChannel.setMethodCallHandler(null)
    }

    /** Listen only while the launcher is in front. */
    fun start() {
        if (!listener.canDetectOrientation()) return
        listener.enable()
        updateSuggestion() // may still be held sideways from before
    }

    fun stop() {
        listener.disable()
        handler.removeCallbacks(settle)
        pending = held
        setSuggesting(false)
    }

    /** Back to portrait when leaving, so Home always opens upright. */
    fun reset() {
        lockTo(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "rotate" -> {
                if (suggesting) lockTo(held)
                setSuggesting(false)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun lockTo(orientation: Int) {
        activity.requestedOrientation = orientation
    }

    private fun updateSuggestion() {
        setSuggesting(autoRotateOn() && held != activity.requestedOrientation)
    }

    private fun setSuggesting(value: Boolean) {
        if (value == suggesting) return
        suggesting = value
        methodChannel.invokeMethod("onSuggestion", value)
    }

    /** Respect the phone's rotation lock: no suggestions while it's on. */
    private fun autoRotateOn(): Boolean =
        Settings.System.getInt(activity.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) == 1

    /**
     * Maps the sensor angle to an orientation, or null when it's near a
     * diagonal (or lying flat), so wobbling between two doesn't count.
     * Upside-down portrait is treated as portrait.
     */
    private fun orientationFor(degrees: Int): Int? {
        if (degrees == OrientationEventListener.ORIENTATION_UNKNOWN) return null
        return when {
            degrees <= MARGIN || degrees >= 360 - MARGIN -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            degrees in 180 - MARGIN..180 + MARGIN -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            degrees in 90 - MARGIN..90 + MARGIN -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            degrees in 270 - MARGIN..270 + MARGIN -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> null
        }
    }

    companion object {
        const val METHOD_CHANNEL = "com.arun.minimal_launcher/rotation"

        /** Degrees either side of upright / sideways that still count as it. */
        private const val MARGIN = 30

        /** How long the phone must stay in a new orientation before we ask. */
        private const val SETTLE_MS = 400L
    }
}
