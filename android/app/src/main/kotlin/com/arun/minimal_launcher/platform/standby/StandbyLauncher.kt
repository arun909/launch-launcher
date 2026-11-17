package com.arun.minimal_launcher.platform.standby

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log

/**
 * Opens [StandbyActivity] from the background, the way alarm clocks do.
 *
 * Android blocks background apps from opening screens (only the running home
 * app may), so the clock is opened by a silent full-screen notification:
 * with the phone locked or the screen off, Android opens its screen over the
 * lock screen and turns the display on. The notification is gone as soon as
 * the clock is up. Without that permission it falls back to opening the
 * screen directly, which works while this is the running home app.
 */
object StandbyLauncher {

    private const val TAG = "Standby"
    private const val CHANNEL = "standby_open"
    private const val ID = 7002

    /** When the clock was last asked for: it takes a moment to come up. */
    private var requestedAt = 0L

    /** The clock came up since it was last asked for (even if closed since). */
    private var shownSinceRequest = false

    fun open(context: Context, turnScreenOn: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (now - requestedAt < 3_000) return
        requestedAt = now
        shownSinceRequest = false
        val intent = Intent(context, StandbyActivity::class.java)
            .putExtra(StandbyActivity.EXTRA_TURN_SCREEN_ON, turnScreenOn)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        if (canUseFullScreen(context)) {
            Log.i(TAG, "opening the clock (full-screen notification)")
            post(context, intent)
            // Not up in a moment (an OEM ignoring it): try directly too.
            Handler(Looper.getMainLooper()).postDelayed({
                if (!shownSinceRequest && !StandbyActivity.isOpen) start(context, intent)
            }, 1_500)
        } else {
            start(context, intent)
        }
    }

    /** The clock is up: the notification has done its job. */
    fun clear(context: Context) {
        requestedAt = 0L
        shownSinceRequest = true
        context.getSystemService(NotificationManager::class.java).cancel(ID)
    }

    /** Notifications on and, on Android 14+, full-screen ones allowed. */
    fun canUseFullScreen(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()
    }

    /** Where the missing permission is switched on. */
    fun openSettings(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val intent = if (!manager.areNotificationsEnabled() || Build.VERSION.SDK_INT < 34) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${context.packageName}"))
        }
        runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun start(context: Context, intent: Intent) {
        Log.i(TAG, "opening the clock (directly)")
        runCatching { context.startActivity(intent) }.onFailure { Log.w(TAG, "couldn't open the clock", it) }
    }

    private fun post(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            // High importance, as full-screen notifications need; no sound or buzz.
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Opening the standby clock", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Shows the clock when the phone is locked and on its side. Silent."
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                }
            )
        }
        val pending = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(context)
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Standby clock")
            .setCategory(Notification.CATEGORY_ALARM)
            .setFullScreenIntent(pending, true)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setShowWhen(false)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(10_000)
        manager.notify(ID, builder.build())
    }
}
