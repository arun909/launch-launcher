package com.arun.minimal_launcher.platform.icons

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import kotlin.math.roundToInt

/**
 * Draws one app icon in an [IconStyle]: the app's own icon masked to a shape,
 * or a line glyph (bundled pack or Android's monochrome layer) on a plate.
 *
 * [radiusPercent] is the corner radius as a percentage of the size
 * (0 = square, 50 = circle); null uses the phone's own icon mask.
 * All methods are blocking; call them off the main thread.
 */
class IconRenderer(private val store: IconPackStore, private val resources: android.content.res.Resources) {

    /** Lazily resolved inputs for one app. */
    class AppSource(label: () -> String, original: () -> Drawable?, val iconFor: (pack: String) -> String?) {
        val label: String by lazy(label)
        val original: Drawable? by lazy(original)
    }

    /**
     * [override] is "original", "<pack>:<icon name>", or null for the style's
     * own choice.
     */
    fun render(app: AppSource, sizePx: Int, radiusPercent: Int?, style: IconStyle, override: String?): Bitmap? {
        if (override == OVERRIDE_ORIGINAL) return app.original?.let { original(it, sizePx, radiusPercent, style) }
        val color by lazy { glyphColor(app, style) }

        // A chosen pack icon applies even when the style keeps original icons.
        parseRef(override)?.let { (pack, name) ->
            store.glyph(pack, name)?.let { return plated(sizePx, radiusPercent, style, color) { c, box -> drawGlyph(c, box, it, style, color) } }
        }
        if (style.isOriginal) return app.original?.let { original(it, sizePx, radiusPercent, style) }
        for (source in style.sources) {
            if (source == IconStyle.THEMED) {
                monochromeOf(app.original)?.let { return themed(it, sizePx, radiusPercent, style, color) }
            } else {
                val glyph = app.iconFor(source)?.let { store.glyph(source, it) } ?: continue
                return plated(sizePx, radiusPercent, style, color) { c, box -> drawGlyph(c, box, glyph, style, color) }
            }
        }
        return when (style.fallback) {
            IconStyle.THEMED -> monochromeOf(app.original)?.let { themed(it, sizePx, radiusPercent, style, color) }
                ?: generatedMonochrome(app.original)?.let { themed(it, sizePx, radiusPercent, style, color) }
                ?: letter(app.label, sizePx, radiusPercent, style, color)
            IconStyle.LETTER -> letter(app.label, sizePx, radiusPercent, style, color)
            IconStyle.GRAYSCALE -> app.original?.let { grayscale(original(it, sizePx, radiusPercent, style)) }
            else -> app.original?.let { original(it, sizePx, radiusPercent, style) }
        }
    }

    /** A pack icon on its own (for the icon picker). */
    fun renderGlyph(ref: String, sizePx: Int, radiusPercent: Int?, style: IconStyle, color: Int): Bitmap? {
        val (pack, name) = parseRef(ref) ?: return null
        val glyph = store.glyph(pack, name) ?: return null
        return plated(sizePx, radiusPercent, style, color) { c, box -> drawGlyph(c, box, glyph, style, color) }
    }

    fun glyphColor(app: AppSource, style: IconStyle): Int =
        if (style.appColor) app.original?.let(::dominantColor) ?: NEUTRAL_APP_COLOR else style.color

    // --- glyph styles ------------------------------------------------------------

    private inline fun plated(
        sizePx: Int,
        radiusPercent: Int?,
        style: IconStyle,
        color: Int,
        drawContent: (Canvas, RectF) -> Unit,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val plate = plateColor(style, color)
        if (plate != null) {
            canvas.drawPath(shapePath(sizePx, radiusPercent), Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = plate })
        }
        // Without a plate there's no edge to keep clear of, so the glyph grows.
        val scale = if (plate == null) (style.glyphScale * 1.3f).coerceAtMost(1f) else style.glyphScale
        val inset = sizePx * (1 - scale) / 2
        drawContent(canvas, RectF(inset, inset, sizePx - inset, sizePx - inset))
        return bitmap
    }

    private fun drawGlyph(canvas: Canvas, box: RectF, glyph: IconPackStore.Glyph, style: IconStyle, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        canvas.save()
        canvas.translate(box.left, box.top)
        canvas.scale(box.width() / 100f, box.height() / 100f)
        for (op in glyph.ops) {
            if (op.kind == 'S') {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = style.strokeWidth * op.strokeRatio
            } else {
                paint.style = Paint.Style.FILL
            }
            canvas.drawPath(op.path, paint)
        }
        canvas.restore()
    }

    private fun themed(mono: Drawable, sizePx: Int, radiusPercent: Int?, style: IconStyle, color: Int): Bitmap =
        plated(sizePx, radiusPercent, style, color) { canvas, box ->
            // The layer is 108dp with logos inside roughly the middle 56dp.
            val layer = box.width() * 108f / 56f
            val pad = ((layer - box.width()) / 2).roundToInt()
            val d = mono.constantState?.newDrawable()?.mutate() ?: mono.mutate()
            d.setBounds(box.left.roundToInt() - pad, box.top.roundToInt() - pad, box.right.roundToInt() + pad, box.bottom.roundToInt() + pad)
            d.colorFilter = PorterDuffColorFilter(color, PorterDuff.Mode.SRC_IN)
            d.draw(canvas)
        }

    private fun letter(label: String, sizePx: Int, radiusPercent: Int?, style: IconStyle, color: Int): Bitmap =
        plated(sizePx, radiusPercent, style, color) { canvas, box ->
            val text = label.trim().firstOrNull()?.uppercase() ?: "?"
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                textSize = box.height() * 0.8f
                textAlign = Paint.Align.CENTER
            }
            val bounds = android.graphics.Rect()
            paint.getTextBounds(text, 0, text.length, bounds)
            canvas.drawText(text, box.centerX(), box.centerY() - bounds.exactCenterY(), paint)
        }

    private fun plateColor(style: IconStyle, color: Int): Int? = when (style.background) {
        IconStyle.BG_NONE -> null
        IconStyle.BG_BLACK -> Color.BLACK
        IconStyle.BG_GLASS -> 0x2EFFFFFF
        IconStyle.BG_TINTED -> Color.rgb(
            (Color.red(color) * 0.22f + 10).roundToInt(),
            (Color.green(color) * 0.22f + 10).roundToInt(),
            (Color.blue(color) * 0.22f + 10).roundToInt(),
        )
        else -> DARK_PLATE
    }

    private fun shapePath(sizePx: Int, radiusPercent: Int?): Path {
        if (radiusPercent == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mask = AdaptiveIconDrawable(ColorDrawable(0), ColorDrawable(0))
            mask.setBounds(0, 0, sizePx, sizePx)
            return Path(mask.iconMask)
        }
        val r = sizePx * (radiusPercent ?: 50).coerceIn(0, 50) / 100f
        return Path().apply { addRoundRect(0f, 0f, sizePx.toFloat(), sizePx.toFloat(), r, r, Path.Direction.CW) }
    }

    // --- the app's own icon ------------------------------------------------------

    /**
     * The app's own icon in the chosen shape. Adaptive icons get their layers
     * masked to it; older icons that already fill the shape are scaled to fill
     * it, and the rest sit on a plate (see [IconStyle.legacyBackground]).
     */
    fun original(drawable: Drawable, sizePx: Int, radiusPercent: Int?, style: IconStyle): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && drawable is AdaptiveIconDrawable) {
            // The phone's own rendering for its own shape.
            if (radiusPercent == null) return renderPlain(drawable, sizePx)
            return adaptive(drawable, sizePx, radiusPercent)
        }
        if (style.legacyBackground == IconStyle.LEGACY_KEEP) return renderPlain(drawable, sizePx)
        return legacy(drawable, sizePx, radiusPercent, style)
    }

    private fun grayscale(source: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val matrix = ColorMatrix().apply { setSaturation(0f) }
        matrix.postConcat(ColorMatrix().apply { setScale(0.82f, 0.82f, 0.82f, 1f) })
        Canvas(out).drawBitmap(source, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG).apply { colorFilter = ColorMatrixColorFilter(matrix) })
        source.recycle()
        return out
    }

    private fun renderPlain(drawable: Drawable, sizePx: Int): Bitmap {
        // Rendering through a Canvas handles bitmap, vector and adaptive icons alike.
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(Canvas(bitmap))
        return bitmap
    }

    /** An adaptive icon's layers through [radiusPercent]'s shape. */
    private fun adaptive(drawable: AdaptiveIconDrawable, sizePx: Int, radiusPercent: Int?): Bitmap {
        val content = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(content)
        // Layers are 108dp with the visible 72dp in the middle, so they
        // extend a quarter of the icon size past each edge.
        val extra = sizePx / 4
        for (layer in listOf(drawable.background, drawable.foreground)) {
            layer ?: continue
            layer.setBounds(-extra, -extra, sizePx + extra, sizePx + extra)
            layer.draw(canvas)
        }
        return masked(content, sizePx, radiusPercent)
    }

    /**
     * An older (non-adaptive) icon in [radiusPercent]'s shape. If the drawing
     * already fills the shape once its transparent margin is cut off (round
     * or squarish logos), it's scaled to fill it; otherwise it's centred on a
     * plate so nothing is cut off.
     */
    private fun legacy(drawable: Drawable, sizePx: Int, radiusPercent: Int?, style: IconStyle): Bitmap {
        val raw = renderPlain(drawable, sizePx)
        val bounds = opaqueBounds(raw) ?: return raw
        val shape = shapePath(sizePx, radiusPercent)
        val content = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(content)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if (fillsShape(raw, bounds, shape, sizePx)) {
            // Slightly past the edges, so no sliver of transparency shows.
            val o = sizePx * 0.015f
            canvas.drawBitmap(raw, bounds, RectF(-o, -o, sizePx + o, sizePx + o), paint)
        } else {
            canvas.drawColor(legacyPlate(raw, style))
            // Rounder shapes cut more of the corners, so leave a wider margin.
            val roundness = (radiusPercent ?: 50).coerceIn(0, 50) / 50f
            val inner = sizePx * (1 - 2 * (LEGACY_MARGIN + LEGACY_ROUND_MARGIN * roundness))
            val scale = inner / maxOf(bounds.width(), bounds.height())
            val w = bounds.width() * scale
            val h = bounds.height() * scale
            canvas.drawBitmap(raw, bounds, RectF((sizePx - w) / 2, (sizePx - h) / 2, (sizePx + w) / 2, (sizePx + h) / 2), paint)
        }
        raw.recycle()
        return masked(content, sizePx, radiusPercent)
    }

    /** Paints [content] through the shape, anti-aliased (clipPath would leave jagged edges). */
    private fun masked(content: Bitmap, sizePx: Int, radiusPercent: Int?): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(content, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        Canvas(bitmap).drawPath(shapePath(sizePx, radiusPercent), paint)
        content.recycle()
        return bitmap
    }

    private fun legacyPlate(raw: Bitmap, style: IconStyle): Int {
        if (style.legacyBackground == IconStyle.LEGACY_TINTED) {
            val hue = dominantHue(raw)
            if (hue != null) return Color.HSVToColor(floatArrayOf(hue, 0.12f, 1f))
        }
        return Color.WHITE
    }

    /** Bounds of the visible (non-transparent) part of [bitmap], or null if there is none. */
    private fun opaqueBounds(bitmap: Bitmap): android.graphics.Rect? {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        var left = w
        var top = h
        var right = -1
        var bottom = -1
        for (y in 0 until h) for (x in 0 until w) {
            if (pixels[y * w + x] ushr 24 > OPAQUE_ALPHA) {
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
            }
        }
        return if (right < left) null else android.graphics.Rect(left, top, right + 1, bottom + 1)
    }

    /**
     * True if [bounds] of [raw], stretched over the whole icon, covers nearly
     * all of [shape] with solid pixels and isn't far from square.
     */
    private fun fillsShape(raw: Bitmap, bounds: android.graphics.Rect, shape: Path, sizePx: Int): Boolean {
        val aspect = bounds.width().toFloat() / bounds.height()
        if (aspect < 0.85f || aspect > 1.18f) return false
        val region = android.graphics.Region().apply { setPath(shape, android.graphics.Region(0, 0, sizePx, sizePx)) }
        var inside = 0
        var solid = 0
        for (i in 0 until FILL_SAMPLES) for (j in 0 until FILL_SAMPLES) {
            val x = (i + 0.5f) * sizePx / FILL_SAMPLES
            val y = (j + 0.5f) * sizePx / FILL_SAMPLES
            if (!region.contains(x.toInt(), y.toInt())) continue
            inside++
            val rx = (bounds.left + x / sizePx * bounds.width()).toInt().coerceIn(0, raw.width - 1)
            val ry = (bounds.top + y / sizePx * bounds.height()).toInt().coerceIn(0, raw.height - 1)
            if (Color.alpha(raw.getPixel(rx, ry)) > SOLID_ALPHA) solid++
        }
        return inside > 0 && solid >= inside * 0.97f
    }

    /**
     * Android 16-style generated monochrome layer for icons without one
     * (AOSP's [MonochromeIconFactory]).
     */
    private fun generatedMonochrome(drawable: Drawable?): Drawable? {
        if (drawable == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return MonochromeIconFactory(GENERATED_MONO_PX).wrap(drawable, resources)
    }

    private fun monochromeOf(drawable: Drawable?): Drawable? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && drawable is AdaptiveIconDrawable) drawable.monochrome
        else null

    /**
     * The icon's most common vivid hue, as a soft pastel that reads well on a
     * dark plate; [NEUTRAL_APP_COLOR] for icons without a clear colour.
     */
    private fun dominantColor(drawable: Drawable): Int {
        val small = renderPlain(drawable, 32)
        val hue = dominantHue(small)
        small.recycle()
        return if (hue == null) NEUTRAL_APP_COLOR else Color.HSVToColor(floatArrayOf(hue, 0.42f, 1f))
    }

    /** The most common vivid hue in [bitmap], or null if it has no clear colour. */
    private fun dominantHue(bitmap: Bitmap): Float? {
        val step = maxOf(1, bitmap.width / 32)
        val weights = FloatArray(HUE_BUCKETS)
        val hueSums = FloatArray(HUE_BUCKETS)
        val hsv = FloatArray(3)
        var total = 0f
        for (y in 0 until bitmap.height step step) for (x in 0 until bitmap.width step step) {
            val px = bitmap.getPixel(x, y)
            if (Color.alpha(px) < 128) continue
            Color.colorToHSV(px, hsv)
            total += 1f
            val w = hsv[1] * hsv[2]
            if (w < 0.15f) continue
            val bucket = (hsv[0] / 360f * HUE_BUCKETS).toInt().coerceIn(0, HUE_BUCKETS - 1)
            weights[bucket] += w
            hueSums[bucket] += hsv[0] * w
        }
        val best = weights.indices.maxByOrNull { weights[it] } ?: return null
        if (total == 0f || weights[best] < total * 0.04f) return null
        return hueSums[best] / weights[best]
    }

    companion object {
        const val OVERRIDE_ORIGINAL = "original"

        private const val DARK_PLATE = 0xFF1E1F22.toInt()
        private const val NEUTRAL_APP_COLOR = 0xFFE3E3E3.toInt()
        private const val HUE_BUCKETS = 24

        /** Margin around older icons on a plate, as a fraction of the size; rounder shapes add the second. */
        private const val LEGACY_MARGIN = 0.12f
        private const val LEGACY_ROUND_MARGIN = 0.06f

        /** Size the monochrome layers are generated at (they're scaled when drawn). */
        private const val GENERATED_MONO_PX = 192

        private const val OPAQUE_ALPHA = 24
        private const val SOLID_ALPHA = 200
        private const val FILL_SAMPLES = 24

        /** "<pack>:<icon name>" -> (pack, name). */
        fun parseRef(ref: String?): Pair<String, String>? {
            val colon = ref?.indexOf(':') ?: return null
            if (colon <= 0 || colon == ref.length - 1) return null
            return ref.substring(0, colon) to ref.substring(colon + 1)
        }
    }
}
