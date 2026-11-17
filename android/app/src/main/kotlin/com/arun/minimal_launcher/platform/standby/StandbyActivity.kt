package com.arun.minimal_launcher.platform.standby

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.OrientationEventListener
import android.view.WindowManager
import com.arun.minimal_launcher.platform.DisplayRefreshRate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

/**
 * The standby clock, sideways, over the lock screen. Opened by
 * [StandbyMonitor] (or "Show now" in settings, with [EXTRA_PREVIEW]).
 *
 * It closes when the phone is turned back upright, when the screen goes off,
 * on a tap (which also asks to unlock), or when covered for a few seconds.
 * The screen stays on while it's up ([StandbyMonitor.keepOn]; otherwise
 * only while charging). It runs at the
 * display's lowest refresh rate.
 */
class StandbyActivity : FlutterActivity() {

    private val handler = Handler(Looper.getMainLooper())
    private var preview = false

    /** Opened from the lock-screen button or tile: stays until unlocked. */
    private var manual = false

    private var closing = false
    private val closeUpright = Runnable {
        closing = false
        if (!preview && !manual) close("turned upright")
    }

    private val orientation by lazy {
        object : OrientationEventListener(this, SensorManager.SENSOR_DELAY_NORMAL) {
            override fun onOrientationChanged(degrees: Int) {
                when (StandbyMonitor.isSideways(degrees)) {
                    false -> if (!closing) {
                        closing = true
                        handler.postDelayed(closeUpright, 600)
                    }
                    true -> {
                        closing = false
                        handler.removeCallbacks(closeUpright)
                    }
                    null -> {}
                }
            }
        }
    }

    /** Covered for a while (put in a pocket, face down): close. */
    private val closeCovered = Runnable { if (!preview) close("covered") }

    private val proximity = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (Proximity.isNear(event.sensor, event)) handler.postDelayed(closeCovered, COVERED_MS)
            else handler.removeCallbacks(closeCovered)
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val power = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) = updateKeepOn()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preview = intent.getBooleanExtra(EXTRA_PREVIEW, false)
        manual = intent.getBooleanExtra(EXTRA_MANUAL, false)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
        applyTurnScreenOn(intent)
        current = WeakReference(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        preview = intent.getBooleanExtra(EXTRA_PREVIEW, false)
        // Asked for by hand: keep it that way, even if it was opened automatically.
        manual = manual || intent.getBooleanExtra(EXTRA_MANUAL, false)
        applyTurnScreenOn(intent)
    }

    /** Opened with the screen off (placed sideways after locking): light it. */
    private fun applyTurnScreenOn(intent: Intent) {
        val on = intent.getBooleanExtra(EXTRA_TURN_SCREEN_ON, false)
        if (Build.VERSION.SDK_INT >= 27) {
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
    }

    override fun onResume() {
        super.onResume()
        isShowing = true
        StandbyLauncher.clear(this)
        StandbyMonitor.onClockShown()
        DisplayRefreshRate.requestLowest(this)
        if (orientation.canDetectOrientation()) orientation.enable()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        registerReceiver(power, filter)
        Proximity.sensor(this)?.let {
            (getSystemService(Context.SENSOR_SERVICE) as SensorManager)
                .registerListener(proximity, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        updateKeepOn()
    }

    override fun onPause() {
        isShowing = false
        orientation.disable()
        handler.removeCallbacks(closeUpright)
        closing = false
        runCatching { unregisterReceiver(power) }
        (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(proximity)
        handler.removeCallbacks(closeCovered)
        super.onPause()
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        isShowing = false
        super.onDestroy()
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = StandbyEngine.get(context)

    /** Kept between showings, see [StandbyEngine]. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /** Plugins were registered when the engine was made. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    private fun close(why: String) {
        Log.i("Standby", "clock closed: $why")
        finish()
    }

    /** A tap: ask to unlock (the clock closes once unlocked), or just close. */
    fun dismiss() {
        Log.i("Standby", "clock tapped")
        StandbyMonitor.dismissed = true
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (keyguard.isKeyguardLocked && Build.VERSION.SDK_INT >= 26) {
            keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = finish()
            })
        } else {
            finish()
        }
    }

    private fun updateKeepOn() {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val charging = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        if (charging || preview || manual || StandbyMonitor.keepOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    companion object {
        /** Opened from settings: stays open upright, keeps the screen on. */
        const val EXTRA_PREVIEW = "preview"

        /** How long covered before the clock closes. */
        private const val COVERED_MS = 3_000L

        /** From the lock-screen button or tile: stays until unlocked or tapped. */
        const val EXTRA_MANUAL = "manual"

        /** Opened while the screen is off: turn it on. */
        const val EXTRA_TURN_SCREEN_ON = "turnScreenOn"

        private var current: WeakReference<StandbyActivity>? = null

        /** In front right now. */
        var isShowing = false
            private set

        /** Created and not yet finished (in front or not). */
        val isOpen: Boolean
            get() = current?.get()?.let { !it.isFinishing } ?: false

        /** The keep-screen-on setting changed. */
        fun refreshKeepOn() {
            current?.get()?.updateKeepOn()
        }

        fun closeIfOpen() {
            current?.get()?.finish()
        }

        fun dismissCurrent() {
            current?.get()?.dismiss()
        }
    }
}
