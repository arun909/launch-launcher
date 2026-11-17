package com.arun.minimal_launcher.platform

import android.app.Activity
import android.os.Build
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import java.util.WeakHashMap

/**
 * Asks Android to run the launcher at the screen's highest refresh rate.
 *
 * Some OEMs (vivo/iQOO "smart switch" among them) run apps they don't know at
 * 60 Hz while their own launcher gets 90/120 Hz. Two requests are made:
 *
 *  1. Window level: prefer the display mode with the highest refresh rate.
 *  2. Surface level (Android 11+): tell the compositor that Flutter's
 *     SurfaceView content is drawn at that rate, the same signal games and
 *     video players use.
 *
 * Both are preferences. If the user picked 60 Hz in Display settings, or
 * battery saver is on, the system still wins. When nothing is animating the
 * system may still drop to a lower rate to save power.
 */
object DisplayRefreshRate {

    private val attached = WeakHashMap<SurfaceView, Boolean>()

    /** Call from onResume: OEMs may reset the preference when the window refocuses. */
    fun requestHighest(activity: Activity) = request(activity, lowest = false)

    /**
     * The opposite, for the standby clock: the slowest mode the screen has
     * (often 60 Hz, lower on LTPO panels), since it barely moves.
     */
    fun requestLowest(activity: Activity) = request(activity, lowest = true)

    private fun request(activity: Activity, lowest: Boolean) {
        val display = currentDisplay(activity) ?: return
        val best = modeAtSameSize(display, lowest) ?: return

        val attrs = activity.window.attributes
        if (attrs.preferredDisplayModeId != best.modeId || attrs.preferredRefreshRate != best.refreshRate) {
            activity.window.attributes = attrs.apply {
                preferredDisplayModeId = best.modeId
                preferredRefreshRate = best.refreshRate
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Flutter adds its SurfaceView after onCreate; post so it exists.
            activity.window.decorView.post {
                findSurfaceViews(activity.window.decorView).forEach { attach(it, best.refreshRate) }
            }
        }
    }

    private fun attach(view: SurfaceView, fps: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val holder = view.holder
        if (attached.put(view, true) == null) {
            // Re-apply whenever Flutter's surface is (re)created, e.g. after
            // returning from another app.
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(h: SurfaceHolder) = setFrameRate(h.surface, fps)
                override fun surfaceChanged(h: SurfaceHolder, format: Int, width: Int, height: Int) =
                    setFrameRate(h.surface, fps)
                override fun surfaceDestroyed(h: SurfaceHolder) {}
            })
        }
        setFrameRate(holder.surface, fps)
    }

    private fun setFrameRate(surface: Surface, fps: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || !surface.isValid) return
        try {
            surface.setFrameRate(fps, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } catch (_: IllegalStateException) {
            // Surface was released between the check and the call; the
            // callback will apply it to the next one.
        }
    }

    private fun findSurfaceViews(view: View): List<SurfaceView> = when (view) {
        is SurfaceView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { findSurfaceViews(view.getChildAt(it)) }
        else -> emptyList()
    }

    private fun modeAtSameSize(display: Display, lowest: Boolean): Display.Mode? {
        val current = display.mode
        val modes = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
        return if (lowest) modes.minByOrNull { it.refreshRate } else modes.maxByOrNull { it.refreshRate }
    }

    private fun currentDisplay(activity: Activity): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
}
