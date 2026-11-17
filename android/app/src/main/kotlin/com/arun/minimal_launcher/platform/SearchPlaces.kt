package com.arun.minimal_launcher.platform

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.BitmapShader
import android.graphics.Shader
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import com.arun.minimal_launcher.R
import java.io.ByteArrayOutputStream

/** Somewhere hold-to-search can search: a site shown in its card, and the app it belongs to. */
internal class SearchPlace(
    val id: String,
    val label: String,
    /** Its app (icon, and "open in the app"): the first one installed. */
    val packages: List<String>,
    /** Web search address, `%s` = the query. */
    val template: String,
    /** Where it goes with nothing typed. */
    val home: String,
    /** In the bar by default even when none of [packages] is installed. */
    val always: Boolean = false,
    /** Nothing kept: its own web profile, deleted afterwards (Incognito). */
    val private: Boolean = false,
    /** Its icon's glyph when it has no app of its own. */
    val glyph: Int = 0,
) {
    var pkg: String? = null
    var icon: Drawable? = null

    fun url(q: String) = if (q.isBlank()) home else template.replace("%s", Uri.encode(q.trim()))
}

/**
 * The places hold-to-search offers, and which of them are in its bar (and
 * in what order), chosen in the launcher's settings. Shared by
 * [QuickSearchOverlay] and the settings screen (through [InstantChannel]).
 */
internal object SearchPlaces {
    private const val KEY_SHOWN = "quick_search_places"

    fun catalog() = listOf(
        SearchPlace("google", "Google", listOf("com.google.android.googlequicksearchbox", "com.android.chrome"), "https://www.google.com/search?q=%s", "https://www.google.com/", always = true),
        SearchPlace("incognito", "Incognito", emptyList(), "https://www.google.com/search?q=%s", "https://www.google.com/", always = true, private = true, glyph = R.drawable.ic_qs_incognito),
        SearchPlace("chatgpt", "ChatGPT", listOf("com.openai.chatgpt"), "https://chatgpt.com/?q=%s", "https://chatgpt.com/"),
        SearchPlace("claude", "Claude", listOf("com.anthropic.claude"), "https://claude.ai/new?q=%s", "https://claude.ai/new"),
        SearchPlace("perplexity", "Perplexity", listOf("ai.perplexity.app.android"), "https://www.perplexity.ai/search?q=%s", "https://www.perplexity.ai/"),
        SearchPlace("youtube", "YouTube", listOf("com.google.android.youtube"), "https://m.youtube.com/results?search_query=%s", "https://m.youtube.com/"),
        SearchPlace("playstore", "Play Store", listOf("com.android.vending"), "https://play.google.com/store/search?q=%s&c=apps", "https://play.google.com/store/apps", always = true),
        SearchPlace("maps", "Maps", listOf("com.google.android.apps.maps"), "https://www.google.com/maps/search/%s", "https://www.google.com/maps"),
        SearchPlace("amazon", "Amazon", listOf("in.amazon.mShop.android.shopping"), "https://www.amazon.in/s?k=%s", "https://www.amazon.in/"),
        SearchPlace("flipkart", "Flipkart", listOf("com.flipkart.android"), "https://www.flipkart.com/search?q=%s", "https://www.flipkart.com/"),
        SearchPlace("reddit", "Reddit", listOf("com.reddit.frontpage"), "https://www.reddit.com/search/?q=%s", "https://www.reddit.com/"),
        SearchPlace("x", "X", listOf("com.twitter.android"), "https://x.com/search?q=%s", "https://x.com/"),
        SearchPlace("pinterest", "Pinterest", listOf("com.pinterest"), "https://www.pinterest.com/search/pins/?q=%s", "https://www.pinterest.com/"),
        SearchPlace("spotify", "Spotify", listOf("com.spotify.music"), "https://open.spotify.com/search/%s", "https://open.spotify.com/"),
        SearchPlace("github", "GitHub", listOf("com.github.android"), "https://github.com/search?q=%s", "https://github.com/"),
        SearchPlace("wikipedia", "Wikipedia", listOf("org.wikipedia"), "https://en.m.wikipedia.org/w/index.php?search=%s", "https://en.m.wikipedia.org/"),
        SearchPlace("translate", "Translate", listOf("com.google.android.apps.translate"), "https://translate.google.com/?sl=auto&tl=en&text=%s&op=translate", "https://translate.google.com/"),
        SearchPlace("duckduckgo", "DuckDuckGo", listOf("com.duckduckgo.mobile.android"), "https://duckduckgo.com/?q=%s", "https://duckduckgo.com/"),
    )

    /** Every place, with its app (if installed) and icon. */
    fun all(context: Context): List<SearchPlace> = catalog().onEach { resolve(context, it) }

    /** The bar's places, in the bar's order. */
    fun shown(context: Context): List<SearchPlace> {
        val places = all(context)
        val chosen = chosenIds(context) ?: return places.filter { it.pkg != null || it.always }
        val byId = places.associateBy { it.id }
        return chosen.mapNotNull { byId[it] }
    }

    /** The ids chosen in settings, or null if never chosen (the default bar then). */
    fun chosenIds(context: Context): List<String>? =
        prefs(context).getString(KEY_SHOWN, null)?.split(',')?.filter { it.isNotBlank() }

    fun setShown(context: Context, ids: List<String>) {
        val known = catalog().map { it.id }.toSet()
        prefs(context).edit().putString(KEY_SHOWN, ids.filter { it in known }.distinct().joinToString(",")).apply()
    }

    /** The icon as a PNG, for the settings screen. */
    fun iconPng(place: SearchPlace, sizePx: Int): ByteArray? {
        val d = place.icon ?: return null
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        d.setBounds(0, 0, sizePx, sizePx)
        d.draw(canvas)
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun resolve(context: Context, p: SearchPlace) {
        val pm = context.packageManager
        p.pkg = p.packages.firstOrNull { pkg ->
            try {
                pm.getApplicationInfo(pkg, 0).enabled
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }
        p.icon = p.pkg?.let { runCatching { pm.getApplicationIcon(it) }.getOrNull() }?.let { round(it) }
            ?: GlyphIcon(context, p)
    }

    /** [icon] as a circle, like the home screen's icons. */
    fun round(icon: Drawable): Drawable = RoundIcon(icon)

    /**
     * An app icon cut to a circle, with smooth edges: an adaptive icon from
     * its full-bleed layers (so it fills the circle), any other as it is.
     * Drawn once per size into a bitmap, then as a round shader.
     */
    private class RoundIcon(private val src: Drawable) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private var cachedSize = 0

        override fun draw(canvas: Canvas) {
            val size = bounds.width().coerceAtLeast(1)
            if (size != cachedSize) render(size)
            canvas.save()
            canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
            val r = size / 2f
            canvas.drawCircle(r, r, r, paint)
            canvas.restore()
        }

        private fun render(size: Int) {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(bitmap)
            if (src is AdaptiveIconDrawable) {
                // Layers are 108 units with the icon's 72 in the middle: 25% more on each side.
                val inset = size / 4
                val r = Rect(-inset, -inset, size + inset, size + inset)
                src.background?.let { it.bounds = r; it.draw(c) }
                src.foreground?.let { it.bounds = r; it.draw(c) }
            } else {
                src.setBounds(0, 0, size, size)
                src.draw(c)
            }
            paint.shader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            cachedSize = size
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = PixelFormat.TRANSLUCENT
    }

    private fun prefs(context: Context) = context.getSharedPreferences("browser_button", Context.MODE_PRIVATE)

    /**
     * An app-icon-shaped tile for a place without an app here (Incognito, a
     * site whose app isn't installed): a dark rounded square with its glyph,
     * or its first letter, in white.
     */
    private class GlyphIcon(context: Context, private val place: SearchPlace) : Drawable() {
        private val glyph = place.glyph.takeIf { it != 0 }?.let { context.getDrawable(it)?.mutate() }?.apply { setTint(Color.WHITE) }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF2C2C2E.toInt() }
        private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }

        override fun draw(canvas: Canvas) {
            val b = RectF(bounds)
            canvas.drawOval(b, fill)
            if (glyph != null) {
                val inset = (b.width() * 0.22f).toInt()
                glyph.bounds = Rect(bounds.left + inset, bounds.top + inset, bounds.right - inset, bounds.bottom - inset)
                glyph.draw(canvas)
            } else {
                text.textSize = b.height() * 0.46f
                val y = b.centerY() - (text.descent() + text.ascent()) / 2
                canvas.drawText(place.label.take(1).uppercase(), b.centerX(), y, text)
            }
        }

        override fun setAlpha(alpha: Int) {
            fill.alpha = alpha
            text.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {}

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
}
