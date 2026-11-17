package com.arun.minimal_launcher.platform

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Blurs the wallpaper behind the launcher's own window (Android 12+ cross-window
 * blur). Purely visual and scoped to this window: nothing persists, and it
 * clears itself when the window goes away.
 * Mirrors lib/core/platform/window_blur_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/window_blur`
 *   isSupported()              -> Boolean (Android 12+ and blur currently enabled;
 *                                          off e.g. in battery saver)
 *   setBlurRadius({radius})    -> null    (px; 0 = no blur)
 *   getWallpaper({width})      -> {png: ByteArray, exact: Boolean}? (the wallpaper
 *                                          as it fills the screen, [width] px wide.
 *                                          exact: the image itself; otherwise a
 *                                          stand-in: a live wallpaper's preview, or
 *                                          a gradient of the wallpaper's colours.
 *                                          null if there's nothing at all)
 *
 *   requestWallpaperAccess()   -> Boolean (true: already allowed, or not needed
 *                                          (a live wallpaper); false: Android's
 *                                          photo-access dialog is shown, if it
 *                                          still may be; the launcher reloads the
 *                                          wallpaper when it's back in front)
 *
 * The wallpaper image is only read, to draw frosted-glass folders over it.
 */
class WindowBlurChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)

    fun register() = methodChannel.setMethodCallHandler(this)

    fun unregister() = methodChannel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())

            "setBlurRadius" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val radius = (call.argument<Int>("radius") ?: 0).coerceAtLeast(0)
                    activity.window.setBackgroundBlurRadius(radius)
                }
                result.success(null)
            }

            "requestWallpaperAccess" -> {
                // A live wallpaper's preview needs no permission.
                val granted = WallpaperManager.getInstance(activity).wallpaperInfo != null ||
                    activity.checkSelfPermission(wallpaperPermission) == PackageManager.PERMISSION_GRANTED
                if (!granted) activity.requestPermissions(arrayOf(wallpaperPermission), REQUEST_WALLPAPER_ACCESS)
                result.success(granted)
            }

            "getWallpaper" -> {
                val width = (call.argument<Int>("width") ?: 360).coerceIn(16, 2048)
                // Decoding and scaling a photo takes a moment; not on the UI thread.
                Thread {
                    val image = try {
                        wallpaperImage(width)
                    } catch (e: Exception) {
                        Log.w(TAG, "Wallpaper image failed: $e")
                        null
                    }
                    activity.runOnUiThread { result.success(image) }
                }.start()
            }

            else -> result.notImplemented()
        }
    }

    /** What WallpaperManager.getDrawable needs. */
    private val wallpaperPermission =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_IMAGES
        else Manifest.permission.READ_EXTERNAL_STORAGE

    /**
     * The home-screen wallpaper centre-cropped to the screen's shape, as Android
     * shows it, as the `getWallpaper` reply. Works for every kind of wallpaper:
     *  - a picture (or plain colour): the picture itself, with photo access;
     *  - a live wallpaper: it draws itself and apps can't see it, so its preview
     *    image (what the wallpaper picker shows), which is close once blurred;
     *  - otherwise (no access yet, no preview): a gradient of its colours,
     *    which Android shares freely.
     */
    private fun wallpaperImage(width: Int): Map<String, Any>? {
        val manager = WallpaperManager.getInstance(activity)
        val (screenW, screenH) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = activity.windowManager.maximumWindowMetrics.bounds
            b.width() to b.height()
        } else {
            val m = activity.resources.displayMetrics
            m.widthPixels to m.heightPixels
        }
        if (screenW <= 0 || screenH <= 0) return null
        val height = (width.toLong() * screenH / screenW).toInt().coerceAtLeast(1)

        val live = manager.wallpaperInfo
        if (live == null) {
            // getDrawable on a live wallpaper would hand out the default
            // wallpaper instead, hence only for pictures.
            val picture = try {
                manager.drawable
            } catch (e: Exception) {
                Log.w(TAG, "Wallpaper not readable: $e") // No photo access yet.
                null
            }
            if (picture != null) return reply(render(picture, width, height), exact = true, "picture")
        } else {
            // What it shows in each part of the screen, as it reports them.
            LiveWallpaperColors.capture(manager)?.let { return reply(it, exact = false, "live areas") }
            // Else its overall colours, which come from what it actually
            // draws; its preview image may not (vivo's share one preview
            // between all of theirs), so that's only for one that reports none.
            colorsGradient(manager, width, height)?.let { return reply(it, exact = false, "live colours") }
            val preview = try {
                live.loadThumbnail(activity.packageManager)
            } catch (e: Exception) {
                Log.w(TAG, "No live wallpaper preview: $e")
                null
            }
            if (preview != null) return reply(render(preview, width, height), exact = false, "live preview")
            return null
        }
        return colorsGradient(manager, width, height)?.let { reply(it, exact = false, "colours") }
    }

    /** [drawable] centre-cropped into a [width] × [height] bitmap. */
    private fun render(drawable: Drawable, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val dw = drawable.intrinsicWidth
        val dh = drawable.intrinsicHeight
        if (dw <= 0 || dh <= 0) {
            drawable.setBounds(0, 0, width, height) // e.g. a plain colour
        } else {
            val scale = max(width.toFloat() / dw, height.toFloat() / dh)
            val w = (dw * scale).roundToInt()
            val h = (dh * scale).roundToInt()
            val left = (width - w) / 2
            val top = (height - h) / 2
            drawable.setBounds(left, top, left + w, top + h)
        }
        drawable.draw(Canvas(bitmap))
        return bitmap
    }

    /** Top to bottom through the wallpaper's main colours; null before Android 8.1. */
    private fun colorsGradient(manager: WallpaperManager, width: Int, height: Int): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return null
        val colors = manager.getWallpaperColors(WallpaperManager.FLAG_SYSTEM) ?: return null
        val stops = listOfNotNull(colors.primaryColor, colors.secondaryColor, colors.tertiaryColor)
            .map { it.toArgb() }
            .let { if (it.size == 1) it + it else it }
            .toIntArray()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val paint = Paint().apply {
            shader = LinearGradient(0f, 0f, 0f, height.toFloat(), stops, null, Shader.TileMode.CLAMP)
        }
        Canvas(bitmap).drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        return bitmap
    }

    private fun reply(bitmap: Bitmap, exact: Boolean, source: String): Map<String, Any> {
        Log.d(TAG, "Glass wallpaper from $source")
        val png = ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            bitmap.recycle()
            it.toByteArray()
        }
        return mapOf("png" to png, "exact" to exact)
    }

    private fun isSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            activity.getSystemService(WindowManager::class.java).isCrossWindowBlurEnabled

    companion object {
        const val METHOD_CHANNEL = "com.arun.minimal_launcher/window_blur"
        private const val TAG = "WindowBlurChannel"
        private const val REQUEST_WALLPAPER_ACCESS = 4101
    }
}
