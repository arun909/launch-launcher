package com.arun.minimal_launcher.platform

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Outline
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.ViewTreeObserver
import android.widget.AdapterView
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.roundToInt

/** Creates an [AppWidgetPlatformView] for `{appWidgetId, radius}` from Dart's AppWidgetView. */
class AppWidgetViewFactory(
    private val host: AppWidgetHost,
    private val manager: AppWidgetManager,
    private val onScrollable: (appWidgetId: Int, scrollable: Boolean) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    /** The views showing now, by app widget id, so a new radius reaches them. */
    private val live = mutableMapOf<Int, AppWidgetPlatformView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val map = args as? Map<*, *>
        val appWidgetId = (map?.get("appWidgetId") as? Number)?.toInt() ?: -1
        val radius = (map?.get("radius") as? Number)?.toFloat() ?: 0f
        val scale = (map?.get("scale") as? Number)?.toFloat() ?: 1f
        return AppWidgetPlatformView(context, host, manager, appWidgetId, radius, scale, onScrollable) {
            if (live[appWidgetId] === it) live.remove(appWidgetId)
        }.also { live[appWidgetId] = it }
    }

    fun setLook(appWidgetId: Int, radiusDp: Float, scale: Float) {
        live[appWidgetId]?.setLook(radiusDp, scale)
    }
}

/**
 * One app widget, drawn by Android inside the Flutter home screen. Tells the
 * widget its size whenever Flutter resizes it, so it can pick a layout.
 *
 * Disposing only drops the view; the widget stays bound (see AppWidgetsChannel).
 */
class AppWidgetPlatformView(
    context: Context,
    host: AppWidgetHost,
    manager: AppWidgetManager,
    private val appWidgetId: Int,
    radiusDp: Float,
    scale: Float,
    private val onScrollable: (appWidgetId: Int, scrollable: Boolean) -> Unit,
    private val onDisposed: (AppWidgetPlatformView) -> Unit,
) : PlatformView {

    private val root = SizedFrame(context).apply {
        cornerRadius = radiusDp * resources.displayMetrics.density
        widgetScale = scale
    }
    private var scrollable: Boolean? = null

    /** Reports when the widget starts or stops holding a list / grid (its layout can change on any update). */
    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener {
        val now = hasCollection(root)
        if (now != scrollable) {
            scrollable = now
            onScrollable(appWidgetId, now)
        }
    }

    init {
        val info = if (appWidgetId >= 0) manager.getAppWidgetInfo(appWidgetId) else null
        val child: View = if (info != null) {
            host.createView(context, appWidgetId, info).also {
                // The home screen already spaces widgets on its grid (lined up
                // with the icons); Android's extra default padding would only
                // take room from the widget.
                it.setPadding(0, 0, 0, 0)
                root.widget = it
            }
        } else {
            TextView(context).apply {
                text = "Widget unavailable"
                gravity = Gravity.CENTER
                setTextColor(0xB3FFFFFF.toInt())
            }
        }
        root.addView(child, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
    }

    override fun getView(): View = root

    override fun dispose() {
        root.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        root.removeAllViews()
        onDisposed(this)
    }

    fun setLook(radiusDp: Float, scale: Float) {
        root.cornerRadius = radiusDp * root.resources.displayMetrics.density
        if (scale != root.widgetScale) {
            root.widgetScale = scale
            root.requestLayout()
        } else {
            root.enforceRoundedCorners()
        }
    }

    /** Lists, grids and stacks: the only scrolling views a widget can hold. */
    private fun hasCollection(view: View): Boolean = when (view) {
        is AdapterView<*> -> true
        is ViewGroup -> (0 until view.childCount).any { hasCollection(view.getChildAt(it)) }
        else -> false
    }

    private class SizedFrame(context: Context) : FrameLayout(context) {
        var widget: AppWidgetHostView? = null

        /** Corner radius in px, as drawn. */
        var cornerRadius = 0f

        /**
         * How much smaller than its layout size the widget is drawn: it lays
         * itself out at the size it was designed for and is scaled down to fit
         * (as Launcher3 does with appWidgetScale). Touches are mapped through
         * the scale by Android.
         */
        var widgetScale = 1f

        private var reportedSize: SizeF? = null

        private fun unscaled(px: Int) = (px / widgetScale).roundToInt()

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val w = MeasureSpec.getSize(widthMeasureSpec)
            val h = MeasureSpec.getSize(heightMeasureSpec)
            setMeasuredDimension(w, h)
            for (i in 0 until childCount) {
                getChildAt(i).measure(
                    MeasureSpec.makeMeasureSpec(unscaled(w), MeasureSpec.EXACTLY),
                    MeasureSpec.makeMeasureSpec(unscaled(h), MeasureSpec.EXACTLY),
                )
            }
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            for (i in 0 until childCount) {
                getChildAt(i).apply {
                    layout(0, 0, measuredWidth, measuredHeight)
                    pivotX = 0f
                    pivotY = 0f
                    scaleX = widgetScale
                    scaleY = widgetScale
                }
            }
            enforceRoundedCorners()
            reportSize()
        }

        /** Tells the widget the size it's laid out at, so it can pick a layout for it. */
        private fun reportSize() {
            val view = widget ?: return
            if (view.width == 0 || view.height == 0) return
            val density = resources.displayMetrics.density
            val size = SizeF(view.width / density, view.height / density)
            if (size == reportedSize) return
            reportedSize = size
            // Not during layout: the widget may re-inflate itself in response.
            post {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    view.updateAppWidgetSize(Bundle(), listOf(size))
                } else {
                    val w = size.width.toInt()
                    val h = size.height.toInt()
                    @Suppress("DEPRECATION")
                    view.updateAppWidgetSize(null, w, h, w, h)
                }
            }
        }

        /**
         * Rounds the widget's corners the way Android's own launcher does
         * (Launcher3's RoundedCornerEnforcement): clipped to an outline around
         * its background view, so the rounding follows the card it draws, not
         * the transparent space around it. Antialiased, unlike a Flutter clip
         * over this view. Left alone if the widget clips its background itself.
         */
        fun enforceRoundedCorners() {
            val view = widget ?: return
            val background = RoundedCorners.findBackground(view)
            if (cornerRadius <= 0f || background == null || RoundedCorners.hasOptedOut(background)) {
                view.outlineProvider = ViewOutlineProvider.BACKGROUND
                view.clipToOutline = false
                return
            }
            val rect = RoundedCorners.boundsIn(view, background)
            // The outline is in the widget's own (unscaled) space.
            val radius = minOf(cornerRadius / widgetScale, rect.width() / 2f, rect.height() / 2f)
            view.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, outline: Outline) = outline.setRoundRect(rect, radius)
            }
            view.clipToOutline = true
        }

    }
}

/** Launcher3's RoundedCornerEnforcement, for [AppWidgetPlatformView.SizedFrame]. */
private object RoundedCorners {

    /** The widget's background: the view with id `background`, else the one visible view everything sits on. */
    fun findBackground(widget: View): View? {
        val tagged = mutableListOf<View>()
        collectWithId(widget, android.R.id.background, tagged)
        if (tagged.size == 1) return tagged[0]
        return if (widget is ViewGroup && widget.childCount > 0) findUndefinedBackground(widget.getChildAt(0)) else widget
    }

    /** Widgets that set clipToOutline on their own background round it themselves. */
    fun hasOptedOut(background: View): Boolean =
        background.id == android.R.id.background && background.clipToOutline

    /** [child]'s bounds in [parent]'s coordinates. */
    fun boundsIn(parent: View, child: View): Rect {
        val rect = Rect(0, 0, child.width, child.height)
        var v: View? = child
        while (v != null && v !== parent) {
            rect.offset(v.left, v.top)
            v = v.parent as? View
        }
        return rect
    }

    private fun collectWithId(view: View, id: Int, out: MutableList<View>) {
        if (view.id == id) out.add(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) collectWithId(view.getChildAt(i), id, out)
    }

    private fun findUndefinedBackground(current: View): View? {
        if (current.visibility != View.VISIBLE) return null
        if (isVisible(current)) return current
        var last: View? = null
        if (current is ViewGroup) {
            for (i in 0 until current.childCount) {
                val found = findUndefinedBackground(current.getChildAt(i)) ?: continue
                if (last != null) return null
                last = found
            }
        }
        return last
    }

    private fun isVisible(view: View): Boolean =
        view.visibility == View.VISIBLE && (!view.willNotDraw() || view.foreground != null || view.background != null)
}
