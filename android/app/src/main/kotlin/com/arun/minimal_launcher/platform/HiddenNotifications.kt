package com.arun.minimal_launcher.platform

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Hidden apps' notifications, when Settings > Hidden apps > Show
 * notifications is off: dismissed as they arrive, and those already showing
 * when it's switched off (or the listener connects).
 *
 * Runs in the notification listener (MediaListenerService), so it needs
 * notification access. Notifications the user can't swipe away (ongoing,
 * foreground services) can't be dismissed and stay. Saved here, not only in
 * Flutter, so it works while the launcher's UI isn't running.
 */
object HiddenNotifications {
    private const val PREFS = "hidden_notifications"
    private const val KEY_BLOCK = "block"
    private const val KEY_PACKAGES = "packages"

    /** The connected listener, to sweep at once when the setting changes. */
    @Volatile
    var listener: NotificationListenerService? = null

    fun set(context: Context, block: Boolean, packages: Collection<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_BLOCK, block)
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .apply()
        listener?.let { sweep(it) }
    }

    /** Dismisses [sbn] if it's from a hidden app and blocking is on. */
    fun onPosted(service: NotificationListenerService, sbn: StatusBarNotification) {
        val blocked = blockedPackages(service) ?: return
        if (sbn.packageName in blocked && sbn.isClearable) runCatching { service.cancelNotification(sbn.key) }
    }

    /** Dismisses every showing notification from a hidden app. */
    fun sweep(service: NotificationListenerService) {
        val blocked = blockedPackages(service) ?: return
        val showing = runCatching { service.activeNotifications }.getOrNull() ?: return
        val keys = showing.filter { it.packageName in blocked && it.isClearable }.map { it.key }
        if (keys.isNotEmpty()) runCatching { service.cancelNotifications(keys.toTypedArray()) }
    }

    /** The hidden packages, or null when their notifications should show. */
    private fun blockedPackages(context: Context): Set<String>? {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!p.getBoolean(KEY_BLOCK, false)) return null
        return (p.getStringSet(KEY_PACKAGES, null) ?: return null) - context.packageName
    }
}
