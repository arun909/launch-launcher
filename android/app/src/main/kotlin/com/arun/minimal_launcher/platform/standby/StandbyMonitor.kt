package com.arun.minimal_launcher.platform.standby

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.OrientationEventListener

/**
 * Shows the standby clock when the phone is locked and on its side:
 *
 *  - Locked while lying still (on a table or a stand, flat or propped),
 *    with nothing over the proximity sensor: the clock opens at once, if
 *    [onRest] is on. vivo freezes this app ~5 s after the screen goes off,
 *    so this is decided within about a second.
 *  - Locked, then placed sideways: for [ARMED_MS] after the screen goes off
 *    the orientation sensor is read (holding a brief wake lock, as the CPU
 *    would otherwise sleep); sideways opens the clock, turning the screen on.
 *  - Woken while sideways: the clock opens at once, before face unlock can
 *    finish (once it's up, unlocking doesn't close it).
 *  - Turned sideways on the lock screen: the same, after a short settle.
 *  - Just unlocked (face unlock is often done before the phone is turned)
 *    and on the home screen: turned sideways within [UNLOCKED_MS] still
 *    opens it. Not inside other apps, so a video in landscape is left alone.
 *
 * If the screen goes off while the clock is up (timeout, power button), it
 * isn't reopened until the phone is woken again.
 *
 * [StandbyService] keeps this process from being frozen while it's on.
 * Outside those moments nothing is listening, so it costs next to nothing.
 */
object StandbyMonitor {

    private const val TAG = "Standby"
    private const val PREFS = "standby"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_KEEP_ON = "keepOn"
    private const val KEY_ON_REST = "onRest"

    /** How long the phone must stay sideways on the lock screen. */
    private const val SETTLE_MS = 400L

    /** How long after locking placing the phone sideways still opens the clock. */
    private const val ARMED_MS = 30_000L

    /** How long after unlocking, on the home screen, turning sideways still counts. */
    private const val UNLOCKED_MS = 8_000L

    /** Covered: how soon to look again. */
    private const val RECHECK_MS = 2_000L

    private lateinit var app: Context
    private val handler = Handler(Looper.getMainLooper())
    private var registered = false

    private enum class Watch { NONE, LOCK_SCREEN, SCREEN_OFF, UNLOCKED }

    /** The launcher's home screen is in front (set by MainActivity). */
    var homeInFront = false

    private var watch = Watch.NONE

    /** Landscape seen, waiting for it to settle. */
    private var pendingShow = false

    /** No reading yet since watching began: the first sideways one opens at once. */
    private var firstReading = true
    private var lastSideways: Boolean? = null

    /** Locked lying still: open whichever way up it rests. */
    private var restWanted = false
    private var wakeLock: PowerManager.WakeLock? = null

    /** The user tapped to leave the clock: not again until the screen is next woken. */
    var dismissed = false

    val enabled: Boolean
        get() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    /** The clock keeps the screen on while it's up (else: only while charging). */
    var keepOn: Boolean
        get() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_KEEP_ON, true)
        set(value) {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_KEEP_ON, value).apply()
            StandbyActivity.refreshKeepOn()
        }

    /** Also open when locked while the phone lies still, whichever way up. */
    var onRest: Boolean
        get() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ON_REST, true)
        set(value) {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ON_REST, value).apply()
        }

    private val rest by lazy {
        RestDetector(app) {
            Log.i(TAG, "lying still")
            if (watch == Watch.SCREEN_OFF) {
                handler.removeCallbacks(show)
                pendingShow = false
                restWanted = true
                open()
            }
        }
    }

    fun init(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        if (enabled) register()
    }

    fun setEnabled(on: Boolean) {
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, on).apply()
        if (on) {
            register()
            StandbyService.start(app)
        } else {
            unregister()
            StandbyService.stop(app)
        }
    }

    /**
     * Starts [StandbyService] if Standby is on. Android lets a foreground
     * service start only from the foreground (or at boot), so the home screen
     * calls this each time it's shown, in case the service was stopped.
     */
    fun ensureRunning(context: Context) {
        init(context)
        if (enabled) StandbyService.start(app)
    }

    private val show = Runnable { open() }

    private val disarm = Runnable {
        if (watch == Watch.SCREEN_OFF || watch == Watch.UNLOCKED) {
            Log.i(TAG, "no longer armed")
            stopWatching()
        }
    }

    private fun open() {
        pendingShow = false
        val fromScreenOff = watch == Watch.SCREEN_OFF
        Log.i(TAG, "sideways: locked=${locked()} dismissed=$dismissed showing=${StandbyActivity.isShowing} screenOff=$fromScreenOff")
        // Just after the screen goes off it may not be locked yet (vivo
        // locks a few seconds later); dark is enough then.
        val unlocked = watch == Watch.UNLOCKED
        if (unlocked) {
            if (homeInFront && !dismissed && !StandbyActivity.isShowing) launch(false, unlocked = true)
            else Log.i(TAG, "unlocked but not on the home screen: not opening")
            return
        }
        if (!(fromScreenOff || locked()) || dismissed || StandbyActivity.isShowing) return
        if (fromScreenOff) {
            // Sideways in a pocket or bag mustn't light the screen. Blocks
            // other attempts while it checks; covered, it looks again soon
            // (taken out still sideways) for as long as it's armed.
            pendingShow = true
            Proximity.check(app) { near ->
                // Disarmed, or turned upright, meanwhile.
                if (watch != Watch.SCREEN_OFF || (lastSideways != true && !restWanted)) {
                    pendingShow = false
                    return@check
                }
                if (!near) {
                    launch(true)
                } else {
                    Log.i(TAG, "covered: not opening yet")
                    handler.postDelayed(show, RECHECK_MS)
                }
            }
            return
        }
        launch(false)
    }

    private fun launch(fromScreenOff: Boolean, unlocked: Boolean = false) {
        if (!(fromScreenOff || unlocked || locked()) || dismissed || StandbyActivity.isShowing) return
        stopWatching()
        StandbyEngine.warm(app)
        StandbyLauncher.open(app, turnScreenOn = fromScreenOff)
    }

    private val orientation by lazy {
        object : OrientationEventListener(app, SensorManager.SENSOR_DELAY_NORMAL) {
            override fun onOrientationChanged(degrees: Int) {
                val sideways = isSideways(degrees) ?: return
                if (sideways != lastSideways) {
                    lastSideways = sideways
                    Log.i(TAG, "orientation $degrees° sideways=$sideways")
                }
                val first = firstReading
                firstReading = false
                if (sideways && first && watch == Watch.LOCK_SCREEN) {
                    // Woken while already sideways: beat face unlock.
                    handler.removeCallbacks(show)
                    open()
                } else if (sideways && !pendingShow) {
                    pendingShow = true
                    handler.postDelayed(show, SETTLE_MS)
                } else if (!sideways && pendingShow && !restWanted) {
                    pendingShow = false
                    handler.removeCallbacks(show)
                }
            }
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            Log.i(TAG, "${intent.action} locked=${locked()}")
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> {
                    stopWatching()
                    // Not an unlock, even if it says unlocked here: the lock
                    // screen comes up a moment later. Only USER_PRESENT is.
                    // Woken again: a new chance, whatever happened before.
                    dismissed = false
                    // Already up (it was opened with the screen off): it
                    // watches the tilt itself.
                    if (locked() && !StandbyActivity.isOpen) startWatching(Watch.LOCK_SCREEN)
                }
                Intent.ACTION_USER_PRESENT -> {
                    stopWatching()
                    LockedPlayback.onUnlocked()
                    if (!StandbyActivity.isOpen) startWatching(Watch.UNLOCKED)
                }
                Intent.ACTION_SCREEN_OFF -> {
                    stopWatching()
                    // What plays from here to the unlock may stay on the tile.
                    LockedPlayback.onLocked(app)
                    val wasShowing = StandbyActivity.isOpen
                    StandbyActivity.closeIfOpen()
                    // Ready for the next showing, so the clock opens at once.
                    StandbyEngine.warm(app)
                    // The clock timed out or was switched off: leave the screen
                    // off (until it's woken).
                    if (!wasShowing) {
                        dismissed = false
                        startWatching(Watch.SCREEN_OFF)
                    }
                }
            }
        }
    }

    private fun register() {
        if (registered) return
        registered = true
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        app.registerReceiver(receiver, filter)
    }

    private fun unregister() {
        if (!registered) return
        registered = false
        stopWatching()
        LockedPlayback.onUnlocked()
        runCatching { app.unregisterReceiver(receiver) }
        StandbyActivity.closeIfOpen()
    }

    /** The clock is up and watches the tilt itself: stop listening here. */
    fun onClockShown() = stopWatching()

    private fun startWatching(kind: Watch) {
        if (!orientation.canDetectOrientation()) return
        watch = kind
        firstReading = true
        lastSideways = null
        restWanted = false
        if (kind == Watch.SCREEN_OFF) {
            // With the screen off the CPU sleeps and the sensor goes quiet.
            wakeLock = (app.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "minimal_launcher:standby")
                .apply { acquire(ARMED_MS + 1_000) }
            handler.postDelayed(disarm, ARMED_MS)
        } else if (kind == Watch.UNLOCKED) {
            handler.postDelayed(disarm, UNLOCKED_MS)
        }
        orientation.enable()
        if (kind == Watch.SCREEN_OFF && onRest && rest.available) rest.start()
        Log.i(TAG, "watching orientation ($kind)")
    }

    private fun stopWatching() {
        if (watch == Watch.NONE) return
        watch = Watch.NONE
        orientation.disable()
        rest.stop()
        handler.removeCallbacks(show)
        handler.removeCallbacks(disarm)
        pendingShow = false
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun locked(): Boolean =
        (app.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

    /**
     * True near either landscape, false near either portrait, null on the
     * diagonals or lying flat (no decision).
     */
    fun isSideways(degrees: Int): Boolean? {
        if (degrees == OrientationEventListener.ORIENTATION_UNKNOWN) return null
        val d = degrees % 180
        return when {
            d in 60..120 -> true
            d <= 30 || d >= 150 -> false
            else -> null
        }
    }
}
