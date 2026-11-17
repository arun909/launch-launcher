package com.arun.minimal_launcher.platform.standby

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * "Standby clock" in Quick Settings: opens the clock, also from the lock
 * screen's pulled-down panel, and it stays until unlocked. Like the
 * lock-screen button, the system opens it, so vivo's freezer doesn't matter.
 */
class StandbyTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = "Standby clock"
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, StandbyActivity::class.java)
            .putExtra(StandbyActivity.EXTRA_MANUAL, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 2, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            )
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
