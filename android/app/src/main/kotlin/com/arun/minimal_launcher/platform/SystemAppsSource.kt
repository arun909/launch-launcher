package com.arun.minimal_launcher.platform

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import java.io.ByteArrayOutputStream

/**
 * Reads system apps that could be disabled, plus which ones currently hold a
 * default role. Read-only and uses public APIs only; the actual
 * enable/disable goes through the privileged Shizuku service.
 */
class SystemAppsSource(private val context: Context) {

    private val pm: PackageManager = context.packageManager

    /**
     * System apps the user could see in a launcher: anything with a launcher
     * activity (enabled or not), plus anything already disabled by the user.
     *
     * Each map: packageName, label, icon (PNG), enabled, defaultRole (nullable).
     */
    fun listSystemApps(iconPx: Int): List<Map<String, Any?>> {
        val roles = defaultRoleHolders()
        val launchable = launchablePackages()
        return installedApplications()
            .filter { it.flags and ApplicationInfo.FLAG_SYSTEM != 0 }
            .filter { it.packageName != context.packageName }
            .mapNotNull { info ->
                val enabled = isEnabled(info)
                if (info.packageName !in launchable && enabled) return@mapNotNull null
                mapOf(
                    "packageName" to info.packageName,
                    "label" to info.loadLabel(pm).toString(),
                    "icon" to iconPng(info, iconPx),
                    "enabled" to enabled,
                    "defaultRole" to roles[info.packageName],
                )
            }
    }

    /**
     * Package -> role for apps Android depends on right now. Disabling one of
     * these can leave the phone without a home screen, dialer, keyboard...
     */
    fun defaultRoleHolders(): Map<String, String> {
        val roles = HashMap<String, String>()
        // Every usable home app, not just the default: one may be the fallback.
        // Disabled HOME components don't count (several system packages ship
        // a dormant one, e.g. DeviceLockController).
        queryActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), includeDisabled = false)
            .forEach { roles[it] = "home screen" }
        resolveDefault(Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")))
            ?.let { roles[it] = "default browser" }
        context.getSystemService(TelecomManager::class.java)?.defaultDialerPackage
            ?.let { roles[it] = "default phone app" }
        Telephony.Sms.getDefaultSmsPackage(context)?.let { roles[it] = "default SMS app" }
        Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.substringBefore('/')?.let { roles[it] = "current keyboard" }
        return roles
    }

    fun isSystemApp(packageName: String): Boolean = try {
        pm.getApplicationInfo(packageName, PackageManager.MATCH_DISABLED_COMPONENTS).flags and
            ApplicationInfo.FLAG_SYSTEM != 0
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun isEnabled(info: ApplicationInfo): Boolean =
        when (pm.getApplicationEnabledSetting(info.packageName)) {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> false
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            else -> info.enabled // DEFAULT: whatever the manifest says
        }

    private fun installedApplications(): List<ApplicationInfo> {
        val flags = PackageManager.MATCH_DISABLED_COMPONENTS.toLong()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(flags))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(flags.toInt())
        }
    }

    private fun launchablePackages(): Set<String> =
        queryActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), includeDisabled = true)
            .toSet()

    private fun queryActivities(intent: Intent, includeDisabled: Boolean): List<String> {
        val flags = if (includeDisabled) PackageManager.MATCH_DISABLED_COMPONENTS.toLong() else 0L
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(flags))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, flags.toInt())
        }
        return result.map { it.activityInfo.packageName }
    }

    /** The app that handles [intent] by default, or null if the user hasn't chosen one. */
    private fun resolveDefault(intent: Intent): String? {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.resolveActivity(intent, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
        // "android" is the chooser dialog, meaning there's no default.
        return info?.activityInfo?.packageName?.takeIf { it != "android" }
    }

    private fun iconPng(info: ApplicationInfo, sizePx: Int): ByteArray {
        val drawable = pm.getApplicationIcon(info)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }
}
