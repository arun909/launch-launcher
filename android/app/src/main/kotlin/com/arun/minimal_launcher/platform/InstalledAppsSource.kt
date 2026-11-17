package com.arun.minimal_launcher.platform

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.os.Build
import com.arun.minimal_launcher.platform.icons.IconPackStore
import com.arun.minimal_launcher.platform.icons.IconRenderer
import com.arun.minimal_launcher.platform.icons.IconStyle
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
    private val packs = IconPackStore(context.assets) { installedPackageUpdateTimes().keys }
    private val renderer = IconRenderer(packs, context.resources)

    /**
     * Metadata for every launchable activity. This launcher's own entry is
     * included, labelled [SELF_LABEL]; Dart opens the settings screen for it.
     * Each map: id, label, packageName, activityName, lastUpdateTime (ms).
     * Icons are fetched separately via [loadIcons] so Dart can skip the
     * expensive part for apps whose cached icon is still current.
     */
    fun queryLaunchableApps(): List<Map<String, Any>> {
        val updateTimes = installedPackageUpdateTimes()
        return queryLauncherActivities()
            .map { info ->
                val activity = info.activityInfo
                val isSelf = activity.packageName == context.packageName
                mapOf(
                    "id" to idOf(activity.packageName, activity.name),
                    "label" to if (isSelf) SELF_LABEL else info.loadLabel(pm).toString(),
                    "packageName" to activity.packageName,
                    "activityName" to activity.name,
                    "lastUpdateTime" to (updateTimes[activity.packageName] ?: 0L),
                )
            }
    }

    /**
     * PNG bytes per app id, drawn in [style]. Ids that can't be resolved are
     * omitted. [cornerRadius] is a percentage of the icon size (0 = square,
     * 50 = circle); null keeps the phone's own icon mask. [overrides] maps app
     * ids to a per-app choice (see [IconRenderer.render]).
     */
    fun loadIcons(
        ids: List<String>,
        sizePx: Int,
        cornerRadius: Int?,
        style: IconStyle,
        overrides: Map<String, String>,
    ): Map<String, ByteArray> {
        val result = HashMap<String, ByteArray>(ids.size)
        for (id in ids) {
            val component = componentOf(id) ?: continue
            try {
                // Throws here, rather than inside the renderer, if the app is gone.
                val icon = pm.getActivityIcon(component)
                val bitmap = renderer.render(sourceOf(component) { icon }, sizePx, cornerRadius, style, overrides[id])
                if (bitmap != null) result[id] = toPng(bitmap)
            } catch (_: PackageManager.NameNotFoundException) {
                // App was uninstalled between list and icon fetch; skip it.
            }
        }
        return result
    }

    /**
     * Pack icons by "<pack>:<name>" ref, for the icon picker. Glyphs take the
     * colour [style] would give [appId] (its own colour with "App colour").
     */
    fun loadPackIcons(
        refs: List<String>,
        sizePx: Int,
        cornerRadius: Int?,
        style: IconStyle,
        appId: String?,
    ): Map<String, ByteArray> {
        val component = appId?.let(::componentOf)
        val color = if (component != null) {
            renderer.glyphColor(sourceOf(component) { safeIcon(component) }, style)
        } else style.color
        val result = HashMap<String, ByteArray>(refs.size)
        for (ref in refs) {
            renderer.renderGlyph(ref, sizePx, cornerRadius, style, color)?.let { result[ref] = toPng(it) }
        }
        return result
    }

    /** Every icon name in a bundled [pack], sorted. */
    fun packIconNames(pack: String): List<String> = packs.names(pack)

    /** The icon each bundled pack has for [id], keyed by pack (packs without one are left out). */
    fun packIconsFor(id: String): Map<String, String> {
        val component = componentOf(id) ?: return emptyMap()
        return IconPackStore.PACKS.mapNotNull { pack -> packs.iconFor(pack, component)?.let { pack to it } }.toMap()
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

    private fun sourceOf(component: ComponentName, icon: () -> Drawable?) = IconRenderer.AppSource(
        label = {
            try {
                pm.getActivityInfo(component, 0).loadLabel(pm).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                ""
            }
        },
        original = icon,
        iconFor = { pack -> packs.iconFor(pack, component) },
    )

    private fun safeIcon(component: ComponentName): Drawable? = try {
        pm.getActivityIcon(component)
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun toPng(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    companion object {
        /** Name of this launcher's own entry in its drawer. */
        private const val SELF_LABEL = "Launcher Settings"

        fun idOf(packageName: String, activityName: String) = "$packageName/$activityName"

        fun componentOf(id: String): ComponentName? {
            val slash = id.indexOf('/')
            if (slash <= 0 || slash == id.length - 1) return null
            return ComponentName(id.substring(0, slash), id.substring(slash + 1))
        }
    }
}
