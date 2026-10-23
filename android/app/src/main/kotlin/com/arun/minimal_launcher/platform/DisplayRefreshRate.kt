package com.arun.minimal_launcher.platform

import android.app.Activity
import android.os.Build
import android.view.Display

/**
 * Asks Android to run this window at the screen's highest refresh rate.
 *
 * Some OEMs (vivo/iQOO "smart switch" among them) run apps they don't know at
 * 60 Hz while their own launcher gets 90/120 Hz, which makes a third-party
 * launcher feel less smooth. This is only a preference: if the user picked
 * 60 Hz in Display settings, or battery saver is on, the system still wins.
 */
object DisplayRefreshRate {

    fun requestHighest(activity: Activity) {
        val display = currentDisplay(activity) ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (activity.window.attributes.preferredDisplayModeId == best.modeId) return
        activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = best.modeId }
    }

    private fun currentDisplay(activity: Activity): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
}
