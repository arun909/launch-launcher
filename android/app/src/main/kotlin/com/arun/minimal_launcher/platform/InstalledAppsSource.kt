package com.arun.minimal_launcher.platform

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import java.io.ByteArrayOutputStream

/**
 * Reads launchable apps and their icons from [PackageManager].
 *
 * Pure Android logic, no Flutter types, so it can be reused or unit-tested
 * independently of the channel. All methods are blocking: call them off the
 * main thread (see [LauncherChannel]).
 *
 * App identity: an "app" is one launchable activity, identified by
 * `"<packageName>/<activityName>"`. A package with two launcher activities
 * shows up as two entries, matching how other launchers behave.
 */
class InstalledAppsSource(private val context: Context) {

    private val pm: PackageManager = context.packageManager

    /**
     * Metadata for every launchable activity (excluding this launcher itself).
     * Each map: id, label, packageName, activityName, lastUpdateTime (ms).
     * Icons are fetched separately via [loadIcons] so Dart can skip the
     * expensive part for apps whose cached icon is still current.
     */
    fun queryLaunchableApps(): List<Map<String, Any>> {
        val updateTimes = installedPackageUpdateTimes()
        return queryLauncherActivities()
            .filter { it.activityInfo.packageName != context.packageName }
            .map { info ->
                val activity = info.activityInfo
                mapOf(
                    "id" to idOf(activity.packageName, activity.name),
                    "label" to info.loadLabel(pm).toString(),
                    "packageName" to activity.packageName,
                    "activityName" to activity.name,
                    "lastUpdateTime" to (updateTimes[activity.packageName] ?: 0L),
                )
            }
    }

    /** PNG bytes per app id. Ids that can't be resolved are omitted. */
    fun loadIcons(ids: List<String>, sizePx: Int): Map<String, ByteArray> {
        val result = HashMap<String, ByteArray>(ids.size)
        for (id in ids) {
            val component = componentOf(id) ?: continue
            try {
                val drawable = pm.getActivityIcon(component)
                result[id] = drawableToPng(drawable, sizePx)
            } catch (_: PackageManager.NameNotFoundException) {
                // App was uninstalled between list and icon fetch; skip it.
            }
        }
        return result
    }

    /** Intent that launches [id]'s activity, or null if it no longer exists. */
    fun launchIntentFor(id: String): Intent? {
        val component = componentOf(id) ?: return null
        val explicit = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(component)
        val resolved = if (explicit.resolveActivity(pm) != null) explicit
        else pm.getLaunchIntentForPackage(component.packageName)
        return resolved?.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        )
    }

    private fun queryLauncherActivities(): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
    }

    /** One bulk query instead of a getPackageInfo() call per app. */
    private fun installedPackageUpdateTimes(): Map<String, Long> {
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        }
        return packages.associate { it.packageName to it.lastUpdateTime }
    }

    private fun drawableToPng(drawable: Drawable, sizePx: Int): ByteArray {
        // Rendering through a Canvas handles bitmap, vector and adaptive icons alike.
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    companion object {
        fun idOf(packageName: String, activityName: String) = "$packageName/$activityName"

        fun componentOf(id: String): ComponentName? {
            val slash = id.indexOf('/')
            if (slash <= 0 || slash == id.length - 1) return null
            return ComponentName(id.substring(0, slash), id.substring(slash + 1))
        }
    }
}
