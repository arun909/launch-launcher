package com.arun.minimal_launcher.platform.standby

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Does no work: it only keeps the launcher's process from being frozen while
 * Standby is on. vivo's "fast freezer" (and Android's cached-app freezer)
 * freeze a home app soon after it leaves the screen, and a frozen process
 * hears no screen on/off and reads no sensor, so [StandbyMonitor] would never
 * see the phone being locked. A foreground service is never frozen.
 *
 * Its notification doubles as the lock-screen shortcut: a "Show clock"
 * button that opens the clock over the lock screen at any time. The system
 * opens it, so it works even while vivo has the launcher frozen. Silent: no
 * sound, no buzz, and it's posted once, not at each lock.
 */
class StandbyService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = notification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID, notification)
        }
        StandbyMonitor.init(applicationContext)
        return START_STICKY
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            // Default importance so it shows on the lock screen; silent.
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Standby clock shortcut", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "The Show clock button on the lock screen. Silent."
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
            // The earlier, hidden channel.
            manager.deleteNotificationChannel(OLD_CHANNEL)
        }
        val showClock = PendingIntent.getActivity(
            this,
            1,
            Intent(this, StandbyActivity::class.java)
                .putExtra(StandbyActivity.EXTRA_MANUAL, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        @Suppress("DEPRECATION")
        val action = Notification.Action.Builder(android.R.drawable.ic_lock_idle_alarm, "Show clock", showClock).build()
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Standby clock")
            .setContentText("Tap to show the clock until you unlock")
            .setContentIntent(showClock)
            .addAction(action)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_STATUS)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    companion object {
        private const val CHANNEL = "standby_lock"
        private const val OLD_CHANNEL = "standby"
        private const val ID = 7001

        fun start(context: Context) {
            val intent = Intent(context, StandbyService::class.java)
            runCatching {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, StandbyService::class.java))
        }
    }
}

/** After a reboot or an update of the launcher: back on, if Standby was on. */
class StandbyBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        StandbyMonitor.init(context)
        StandbyMonitor.ensureRunning(context)
    }
}
