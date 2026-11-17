package com.arun.minimal_launcher.platform

import android.app.WallpaperColors
import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.RectF
import android.os.Build
import android.util.Log
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * A coarse picture of a live wallpaper as it looks right now: a [COLS] × [ROWS]
 * grid, each cell the colour the wallpaper shows there.
 *
 * Apps can't see what a live wallpaper draws, but since Android 12 the
 * wallpaper itself reports the colours of given areas of the screen (how
 * Android's own launcher tints widgets to what's behind them). That API isn't
 * in the public SDK, so it's reached by reflection, and [capture] returns null
 * wherever the phone doesn't allow it. Read-only: nothing is changed.
 */
object LiveWallpaperColors {
    private const val TAG = "LiveWallpaperColors"
    const val COLS = 9
    const val ROWS = 18

    /** Blocks (call off the UI thread) until every cell has reported, or [timeoutMs]. */
    fun capture(manager: WallpaperManager, timeoutMs: Long = 1500): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val consumerClass: Class<*>
        val add: Method
        val remove: Method
        try {
            consumerClass = Class.forName("android.app.WallpaperManager\$LocalWallpaperColorConsumer")
            add = WallpaperManager::class.java.methods.firstOrNull {
                it.name == "addOnColorsChangedListener" && it.parameterTypes.firstOrNull() == consumerClass
            } ?: return unavailable("no addOnColorsChangedListener")
            remove = WallpaperManager::class.java.getMethod("removeOnColorsChangedListener", consumerClass)
        } catch (e: Throwable) {
            return unavailable(e.toString())
        }

        val regions = ArrayList<RectF>(COLS * ROWS)
        for (r in 0 until ROWS) for (c in 0 until COLS) {
            regions += RectF(c.toFloat() / COLS, r.toFloat() / ROWS, (c + 1f) / COLS, (r + 1f) / ROWS)
        }
        val colors = ConcurrentHashMap<RectF, Int>()
        val done = CountDownLatch(1)
        val consumer = Proxy.newProxyInstance(consumerClass.classLoader, arrayOf(consumerClass)) { proxy, method, args ->
            when (method.name) {
                "onColorsChanged" -> {
                    val area = args?.getOrNull(0) as? RectF
                    val reported = args?.getOrNull(1) as? WallpaperColors
                    if (area != null && reported != null) {
                        colors[area] = reported.primaryColor.toArgb()
                        if (colors.size >= regions.size) done.countDown()
                    }
                    null
                }
                "equals" -> proxy === args?.getOrNull(0)
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "LiveWallpaperColors consumer"
                else -> null
            }
        }
        try {
            // (consumer, regions) on Android 12, (consumer, regions, which) after.
            if (add.parameterTypes.size == 3) add.invoke(manager, consumer, regions, WallpaperManager.FLAG_SYSTEM)
            else add.invoke(manager, consumer, regions)
        } catch (e: Throwable) {
            return unavailable(e.cause?.toString() ?: e.toString())
        }
        done.await(timeoutMs, TimeUnit.MILLISECONDS)
        try {
            remove.invoke(manager, consumer)
        } catch (e: Throwable) {
            Log.w(TAG, "Couldn't stop listening: $e")
        }
        Log.d(TAG, "${colors.size} of ${regions.size} areas reported")
        // Most of the grid, or it's not a picture of the wallpaper.
        if (colors.size < regions.size * 3 / 4) return null

        val bitmap = Bitmap.createBitmap(COLS, ROWS, Bitmap.Config.ARGB_8888)
        val fallback = colors.values.first()
        for ((i, area) in regions.withIndex()) {
            bitmap.setPixel(i % COLS, i / COLS, colors[area] ?: fallback)
        }
        return bitmap
    }

    private fun unavailable(why: String): Bitmap? {
        Log.w(TAG, "Area colours unavailable: $why")
        return null
    }
}
