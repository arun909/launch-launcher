package com.arun.minimal_launcher.platform

import android.accessibilityservice.AccessibilityService
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.LayoutTransition
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Display
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.view.animation.PathInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.arun.minimal_launcher.R
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * "Hold to search" (a settings switch), part of [BrowserButtonService].
 *
 * Touch and hold the bottom centre of the screen over any app: a light line
 * grows under the finger, and when it's full a small search panel pops up
 * from there, keyboard ready. Type, then pick where to search (Google,
 * ChatGPT, Claude, YouTube… whichever apps are installed, last used first),
 * or tap a matching app to open it. The results show in a rounded card
 * floating over the app that was open; its header has open-in-app, full
 * screen and close; tap the query to change it, swipe the header up for
 * full screen or down to put it away.
 *
 * A swipe from the same spot is never caught, so Android's home gesture
 * still works; a hold is the only thing that opens it. Everything here is
 * one overlay window: transitions only move, fade and clip views (the page
 * is resized once per step, never every frame), so they stay smooth.
 *
 * Self-contained: [BrowserButtonService] only creates it and calls [update].
 */
internal class QuickSearchOverlay(
    private val service: AccessibilityService,
    /** Called after it closes, so the service can bring the hold strip back. */
    private val onClosed: () -> Unit,
) {

    private enum class Mode { CLOSED, SEARCH, CARD, FULL }

    private class AppEntry(val label: String, val lower: String, val component: ComponentName, val info: android.content.pm.ResolveInfo) {
        var icon: Drawable? = null
    }

    private val ctx: Context = ContextThemeWrapper(service, android.R.style.Theme_DeviceDefault)
    private val wm = service.getSystemService(WindowManager::class.java)
    private val imm = service.getSystemService(InputMethodManager::class.java)
    private val pm = service.packageManager
    private val main = Handler(Looper.getMainLooper())

    // ---- State ----------------------------------------------------------------

    private var enabled = false
    private var mode = Mode.CLOSED
    private var closing = false

    /** The app in front when it was opened: switching to another closes it. */
    private var lastFront: String? = null
    private var openedOver: String? = null

    private var strip: HoldStrip? = null
    private var stripParams: WindowManager.LayoutParams? = null

    private var root: FrameLayout? = null
    private lateinit var scrim: View

    /** Frosted glass behind the panel: the screen as it was when the hold began, blurred. */
    private lateinit var backdropView: ImageView
    private var backdrop: Bitmap? = null
    private var backdropAt = 0L
    private lateinit var searchHolder: FrameLayout
    private lateinit var searchCard: LinearLayout
    private lateinit var appsRow: LinearLayout
    private lateinit var chipsRow: LinearLayout
    private lateinit var input: EditText
    private lateinit var clearButton: ImageView
    private lateinit var result: LinearLayout
    private lateinit var header: FrameLayout
    private lateinit var handle: View
    private lateinit var openButton: ImageView
    private lateinit var headerIcon: ImageView
    private lateinit var headerTitle: TextView
    private lateinit var fullButton: ImageView
    private lateinit var webBox: FrameLayout
    private var web: WebView? = null
    private var progress: ProgressBar? = null
    private var videoView: View? = null
    private var videoCallback: WebChromeClient.CustomViewCallback? = null
    private var backCallback: Any? = null

    private var provider: SearchPlace? = null
    private var privateMode = false
    private var privateIsolated = false
    private var query = ""
    private var providers: List<SearchPlace> = emptyList()

    private var imeBottom = 0
    private var imeAnimating = false
    private var transition: Animator? = null

    /** The card's clip, in its own coordinates (see [animateFull]). */
    private val clip = RectF()
    private var clipRadius = 0f

    private var apps: List<AppEntry> = emptyList()
    private var appsAt = 0L

    // ---- From the service -------------------------------------------------------

    /**
     * [on]: the switch; [locked]: the lock screen is up; [keyboard]: a
     * keyboard is showing (the strip would sit on its space bar).
     */
    fun update(on: Boolean, locked: Boolean, keyboard: Boolean) {
        enabled = on
        if (!on || locked) {
            hideStrip()
            closeNow()
            return
        }
        if (mode != Mode.CLOSED) return
        if (keyboard) hideStrip() else showStrip()
    }

    /**
     * An app's screen came to the front ([pkg]: a real activity, from the
     * service). Leaving the app it was opened over (home, another app) puts
     * it away. Only real screen changes count: which window Android lists
     * first shifts around while the panel has the focus, and guessing from
     * that could close the panel the moment it opened.
     */
    fun onAppSwitched(pkg: String) {
        if (mode != Mode.CLOSED && openedOver != null && pkg != openedOver) close()
        lastFront = pkg
    }

    fun destroy() {
        hideStrip()
        closeNow()
    }

    // ---- The hold strip ---------------------------------------------------------

    private fun showStrip() {
        if (strip != null) return
        val p = WindowManager.LayoutParams(
            dpi(STRIP_WIDTH_DP),
            dpi(STRIP_HEIGHT_DP),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
            windowAnimations = 0
            title = "Hold to search"
        }
        val v = HoldStrip()
        try {
            wm.addView(v, p)
            strip = v
            stripParams = p
        } catch (_: Exception) {
        }
    }

    /** Puts the strip back on top after another overlay (the full-screen page) covered it. */
    fun raise() {
        val v = strip ?: return
        val p = stripParams ?: return
        runCatching { wm.removeView(v) }
        runCatching { wm.addView(v, p) }
    }

    private fun hideStrip() {
        val v = strip ?: return
        v.cancelHold()
        runCatching { wm.removeView(v) }
        strip = null
    }

    /**
     * The invisible touch strip. A hold grows a soft light line under the
     * finger; when it's full, search opens. Moving (a swipe) or lifting
     * early lets it fade, and Android's own gesture carries on.
     */
    @SuppressLint("ViewConstructor")
    private inner class HoldStrip : View(service) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        private val slop = ViewConfiguration.get(service).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var holding = false
        private var grow: ValueAnimator? = null
        private var level = 0f

        init {
            contentDescription = "Hold to search"
        }

        override fun onDraw(canvas: Canvas) {
            if (level <= 0.001f) return
            val w = lerp(dp(18f), dp(96f), level)
            val h = lerp(dp(3f), dp(5f), level)
            val cx = width / 2f
            val cy = height - dp(9f)
            paint.alpha = (min(1f, level * 1.4f) * 220).toInt()
            paint.setShadowLayer(dp(6f) * level, 0f, 0f, 0x99FFFFFF.toInt())
            canvas.drawRoundRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, h / 2, h / 2, paint)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startHold()
                }
                MotionEvent.ACTION_MOVE ->
                    if (holding && hypot(e.rawX - downX, e.rawY - downY) > slop) cancelHold()
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> cancelHold()
            }
            return true
        }

        private fun startHold() {
            grow?.cancel()
            holding = true
            grow = ValueAnimator.ofFloat(level, 1f).apply {
                startDelay = HOLD_DELAY_MS
                duration = HOLD_MS
                interpolator = PathInterpolator(0.3f, 0f, 0.2f, 1f)
                addUpdateListener {
                    level = it.animatedValue as Float
                    invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    private var cancelled = false
                    override fun onAnimationStart(animation: Animator) = captureBackdrop()

                    override fun onAnimationCancel(animation: Animator) {
                        cancelled = true
                    }

                    override fun onAnimationEnd(animation: Animator) {
                        if (cancelled || !holding) return
                        holding = false
                        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                        open()
                    }
                })
                start()
            }
        }

        fun cancelHold() {
            if (!holding && level <= 0f) return
            holding = false
            grow?.cancel()
            grow = ValueAnimator.ofFloat(level, 0f).apply {
                duration = 160
                addUpdateListener {
                    level = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }
    }

    // ---- Opening and closing ----------------------------------------------------

    private fun open() {
        if (mode != Mode.CLOSED || closing || !enabled) return
        BrowserButtonService.guardMainLooper()
        hideStrip()
        openedOver = lastFront
        providers = loadProviders()
        loadAppsIfStale()
        val r = buildWindow()
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
            windowAnimations = 0
            title = "Quick search"
        }
        try {
            wm.addView(r, p)
        } catch (_: Exception) {
            root = null
            return
        }
        mode = Mode.SEARCH
        watchBack(r)
        // Pops out of the spot that was held.
        searchCard.alpha = 0f
        searchCard.scaleX = 0.35f
        searchCard.scaleY = 0.5f
        searchCard.translationY = dp(28f)
        r.post {
            searchCard.pivotX = searchCard.width / 2f
            searchCard.pivotY = searchCard.height.toFloat()
            searchCard.animate().alpha(1f).setDuration(160).start()
            searchCard.animate()
                .scaleX(1f).scaleY(1f).translationY(0f)
                .setDuration(460)
                .setInterpolator(EMPHASIZED_DECELERATE)
                .start()
            focusInput()
        }
        staggerIn(chipsRow, startDelay = 90)
        showBackdrop()
        scrim.animate().alpha(if (backdropView.drawable != null) GLASS_SCRIM_ALPHA else SCRIM_ALPHA).setDuration(260).start()
    }

    /** Puts everything away, animated. */
    fun close() {
        if (mode == Mode.CLOSED || closing) return
        closing = true
        transition?.cancel()
        hideKeyboard()
        scrim.animate().alpha(0f).setDuration(220).start()
        backdropView.animate().alpha(0f).setDuration(220).start()
        if (searchCard.visibility == View.VISIBLE) {
            searchCard.animate().alpha(0f).scaleX(0.9f).scaleY(0.9f).translationY(dp(20f))
                .setDuration(200).setInterpolator(EMPHASIZED_ACCELERATE).start()
        }
        if (result.visibility == View.VISIBLE) {
            result.pivotX = result.width / 2f
            result.pivotY = result.height.toFloat()
            result.animate().alpha(0f).scaleX(0.94f).scaleY(0.94f).translationY(result.translationY + dp(72f))
                .setDuration(240).setInterpolator(EMPHASIZED_ACCELERATE).start()
        }
        main.postDelayed({ closeNow() }, 250)
    }

    /** Puts everything away at once. */
    private fun closeNow() {
        val r = root ?: run {
            mode = Mode.CLOSED
            closing = false
            return
        }
        transition?.cancel()
        videoView?.let { web?.webChromeClient?.onHideCustomView() }
        unwatchBack(r)
        hideKeyboard()
        runCatching { wm.removeView(r) }
        web?.let {
            it.stopLoading()
            it.destroy()
        }
        endPrivate()
        CookieManager.getInstance().flush()
        web = null
        progress = null
        backdrop = null // Never kept: dropped as soon as it's put away.
        root = null
        provider = null
        query = ""
        mode = Mode.CLOSED
        closing = false
        main.post(onClosed)
    }

    // ---- Building it ------------------------------------------------------------

    @SuppressLint("ClickableViewAccessibility")
    private fun buildWindow(): FrameLayout {
        val r = object : FrameLayout(ctx) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP) back()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        root = r

        backdropView = ImageView(ctx).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            alpha = 0f
            if (Build.VERSION.SDK_INT >= 31) {
                setRenderEffect(RenderEffect.createBlurEffect(dp(BLUR_DP), dp(BLUR_DP), Shader.TileMode.CLAMP))
            }
        }
        r.addView(backdropView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        scrim = View(ctx).apply {
            setBackgroundColor(Color.BLACK)
            alpha = 0f
            setOnClickListener { close() }
        }
        r.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        // -- The search panel
        searchHolder = FrameLayout(ctx).apply {
            layoutTransition = LayoutTransition().apply {
                enableTransitionType(LayoutTransition.CHANGING)
                setDuration(220)
                setInterpolator(LayoutTransition.CHANGING, STANDARD)
            }
        }
        r.addView(
            searchHolder,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
                leftMargin = dpi(SIDE_DP)
                rightMargin = dpi(SIDE_DP)
                bottomMargin = dpi(BOTTOM_DP)
            },
        )
        searchCard = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = panelBackground(dp(PANEL_CORNER_DP))
            elevation = dp(12f)
            setPadding(dpi(12), dpi(14), dpi(12), dpi(12))
            isClickable = true // A tap on the panel isn't a tap on the scrim.
            layoutTransition = LayoutTransition().apply {
                enableTransitionType(LayoutTransition.CHANGING)
                setDuration(220)
                setInterpolator(LayoutTransition.CHANGING, STANDARD)
            }
        }
        searchHolder.addView(searchCard, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        appsRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            visibility = View.GONE
        }
        searchCard.addView(appsRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dpi(6)
        })

        chipsRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        val chipsScroll = HorizontalScrollView(ctx).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            isFillViewport = true
            clipToPadding = false
            addView(chipsRow)
        }
        // Up to six share the row's width exactly (the pill's width); more scroll.
        val spread = providers.size <= 6
        providers.forEachIndexed { i, p ->
            chipsRow.addView(
                tile(p),
                if (spread) {
                    LinearLayout.LayoutParams(0, dpi(TILE_DP), 1f).apply { if (i < providers.size - 1) marginEnd = dpi(8) }
                } else {
                    LinearLayout.LayoutParams(dpi(ICON_DP + 16), dpi(TILE_DP))
                },
            )
        }
        searchCard.addView(chipsScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dpi(8)
        })

        // Circle to Search next to the search pill, both the same height.
        val bottomRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (isInstalled(GOOGLE_APP)) {
            val cts = FrameLayout(ctx).apply {
                background = RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), squircle(dp(26f), 0x1AFFFFFF), null)
                contentDescription = "Circle to Search"
                tooltipText = "Circle to Search"
                setOnClickListener { circleToSearch() }
                pressable(this)
                addView(icon(R.drawable.ic_qs_circle_search, 0xE6FFFFFF.toInt()), FrameLayout.LayoutParams(dpi(24), dpi(24), Gravity.CENTER))
            }
            bottomRow.addView(cts, LinearLayout.LayoutParams(dpi(PILL_DP), dpi(PILL_DP)).apply { marginEnd = dpi(8) })
        }
        bottomRow.addView(searchPill(), LinearLayout.LayoutParams(0, dpi(PILL_DP), 1f))
        searchCard.addView(bottomRow, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        // -- The result card (shown once somewhere to search is picked)
        result = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
            elevation = dp(16f)
            isClickable = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(clip.left.toInt(), clip.top.toInt(), clip.right.toInt(), clip.bottom.toInt(), clipRadius)
                }
            }
            clipToOutline = true
        }
        r.addView(result, FrameLayout.LayoutParams(0, 0, Gravity.TOP or Gravity.START))
        header = buildHeader()
        result.addView(header, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpi(HEADER_DP)))
        webBox = FrameLayout(ctx).apply { setBackgroundColor(Color.BLACK) }
        result.addView(webBox, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        // Made now, while typing, so the first page shows without a wait.
        buildWeb()

        // The keyboard: the panel rides on it frame by frame; the card is laid out again once it settles.
        r.setOnApplyWindowInsetsListener { _, insets ->
            val ime = imeOf(insets)
            if (ime != imeBottom) {
                imeBottom = ime
                if (!imeAnimating) followKeyboard(ime)
                when (mode) {
                    Mode.CARD -> if (transition == null) layoutCard()
                    Mode.FULL -> if (transition == null) layoutFull()
                    else -> {}
                }
            }
            insets
        }
        if (Build.VERSION.SDK_INT >= 30) {
            r.setWindowInsetsAnimationCallback(object : WindowInsetsAnimation.Callback(DISPATCH_MODE_STOP) {
                override fun onPrepare(animation: WindowInsetsAnimation) {
                    if (animation.typeMask and WindowInsets.Type.ime() != 0) imeAnimating = true
                }

                override fun onProgress(insets: WindowInsets, running: MutableList<WindowInsetsAnimation>): WindowInsets {
                    followKeyboard(insets.getInsets(WindowInsets.Type.ime()).bottom)
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimation) {
                    if (animation.typeMask and WindowInsets.Type.ime() != 0) {
                        imeAnimating = false
                        followKeyboard(imeBottom)
                    }
                }
            })
        }
        // Turned sideways: lay the card out for the new size.
        r.addOnLayoutChangeListener { _, l, t, rt, b, ol, ot, ort, ob ->
            if ((rt - l != ort - ol || b - t != ob - ot) && transition == null) {
                when (mode) {
                    Mode.CARD -> layoutCard()
                    Mode.FULL -> layoutFull()
                    else -> {}
                }
            }
        }
        return r
    }

    private fun searchPill(): View {
        val pill = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = squircle(dp(26f), 0x1AFFFFFF)
            setPadding(dpi(16), 0, dpi(6), 0)
        }
        pill.addView(icon(R.drawable.ic_qs_search, 0x99FFFFFF.toInt()), LinearLayout.LayoutParams(dpi(20), dpi(20)))
        input = EditText(ctx).apply {
            background = null
            hint = "Search"
            setHintTextColor(0x66FFFFFF)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
            imeOptions = EditorInfo.IME_ACTION_SEARCH or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setPadding(dpi(12), 0, dpi(8), 0)
            highlightColor = 0x55FFFFFF
            if (Build.VERSION.SDK_INT >= 29) {
                textCursorDrawable = GradientDrawable().apply {
                    setColor(Color.WHITE)
                    setSize(dpi(2), dpi(20))
                }
            }
            setOnEditorActionListener { _, action, event ->
                val enter = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN
                if (action == EditorInfo.IME_ACTION_SEARCH || enter) {
                    providers.firstOrNull()?.let { showResult(it) }
                    true
                } else {
                    false
                }
            }
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    val q = s?.toString().orEmpty()
                    clearButton.visibility = if (q.isEmpty()) View.INVISIBLE else View.VISIBLE
                    showApps(q)
                }
            })
        }
        pill.addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        clearButton = iconButton(R.drawable.ic_qs_close, "Clear", 0x99FFFFFF.toInt()) { input.setText("") }.apply {
            visibility = View.INVISIBLE
        }
        pill.addView(clearButton, LinearLayout.LayoutParams(dpi(40), dpi(40)))
        return pill
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildHeader(): FrameLayout {
        val frame = FrameLayout(ctx).apply { setBackgroundColor(0xFF121212.toInt()) }
        // Grab handle: the header can be swiped (up: full screen, down: away).
        handle = View(ctx).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(2f)
                setColor(0x40FFFFFF)
            }
        }
        frame.addView(handle, FrameLayout.LayoutParams(dpi(32), dpi(4), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            topMargin = dpi(6)
        })
        val h = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpi(14), dpi(6), dpi(4), 0)
        }
        frame.addView(h, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        headerIcon = ImageView(ctx)
        h.addView(headerIcon, LinearLayout.LayoutParams(dpi(22), dpi(22)))
        headerTitle = TextView(ctx).apply {
            setTextColor(0xE6FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dpi(12), 0, dpi(8), 0)
        }
        h.addView(headerTitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        openButton = iconButton(R.drawable.ic_qs_open, "Open in the app", 0xCCFFFFFF.toInt()) { openInApp() }
        h.addView(openButton, LinearLayout.LayoutParams(dpi(44), dpi(44)))
        fullButton = iconButton(R.drawable.ic_web_fullscreen, "Full screen", 0xCCFFFFFF.toInt()) { toggleFull() }
        h.addView(fullButton, LinearLayout.LayoutParams(dpi(44), dpi(44)))
        h.addView(iconButton(R.drawable.ic_qs_close, "Close", 0xCCFFFFFF.toInt()) { close() }, LinearLayout.LayoutParams(dpi(44), dpi(44)))
        frame.setOnTouchListener(HeaderDrag())
        return frame
    }

    /**
     * The page view. [private]: an Incognito one, in its own web profile
     * (its own cookies, storage and cache, deleted when it's put away), so
     * sites work normally inside it and nothing of it is kept; where Android's
     * web view can't do profiles, cookies are switched off instead.
     */
    @SuppressLint("SetJavaScriptEnabled")
    private fun buildWeb(private: Boolean = false) {
        val view = WebView(ctx)
        val isolated = private && usePrivateProfile(view)
        view.apply {
            setBackgroundColor(Color.BLACK)
            isFocusable = true
            isFocusableInTouchMode = true
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                loadWithOverviewMode = true
                useWideViewPort = true
                builtInZoomControls = true
                displayZoomControls = false
                mediaPlaybackRequiresUserGesture = false
                setSupportMultipleWindows(false)
                // Look like Chrome, not an in-app WebView (some sign-ins refuse WebViews).
                userAgentString = userAgentString.replace("; wv)", ")").replace(Regex("Version/\\S+ "), "")
            }
            if (!private) CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            webViewClient = Client()
            webChromeClient = Chrome()
        }
        privateMode = private
        privateIsolated = isolated
        if (private && !isolated) {
            CookieManager.getInstance().setAcceptCookie(false)
            view.settings.cacheMode = WebSettings.LOAD_NO_CACHE
            view.settings.domStorageEnabled = false
        }
        webBox.addView(view, 0, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        if (progress == null) {
            val bar = ProgressBar(ctx, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 100
                visibility = View.GONE
                progressTintList = ColorStateList.valueOf(Color.WHITE)
                progressBackgroundTintList = ColorStateList.valueOf(0x22FFFFFF)
            }
            webBox.addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpi(2), Gravity.TOP))
            progress = bar
        }
        web = view
    }

    private fun usePrivateProfile(view: WebView): Boolean = try {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            ProfileStore.getInstance().getOrCreateProfile(INCOGNITO_PROFILE)
            WebViewCompat.setProfile(view, INCOGNITO_PROFILE)
            true
        } else {
            false
        }
    } catch (e: Exception) {
        android.util.Log.w("QuickSearch", "No Incognito profile", e)
        false
    }

    /** A new page view when switching between Incognito and normal; the old one (and any Incognito data) goes. */
    private fun swapWeb(private: Boolean) {
        val old = web ?: return buildWeb(private)
        webBox.removeView(old)
        old.stopLoading()
        old.destroy()
        endPrivate()
        buildWeb(private)
    }

    /** Throws away everything an Incognito page kept. */
    private fun endPrivate() {
        if (!privateMode) return
        privateMode = false
        if (privateIsolated) {
            // Once its page view is fully gone.
            main.postDelayed({ runCatching { ProfileStore.getInstance().deleteProfile(INCOGNITO_PROFILE) } }, 600)
        } else {
            CookieManager.getInstance().setAcceptCookie(true)
            WebView(ctx).apply {
                clearCache(true)
                destroy()
            }
        }
        privateIsolated = false
    }

    // ---- Search panel contents --------------------------------------------------

    /** One place to search: its app icon at full size (long-press for its name). */
    private fun tile(p: SearchPlace): View {
        val t = FrameLayout(ctx).apply {
            // Unbounded: the ripple blooms around the icon.
            background = RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), null, null)
            contentDescription = "Search ${p.label}"
            tooltipText = p.label
            setOnClickListener { showResult(p) }
            pressable(this)
        }
        t.addView(ImageView(ctx).apply { setImageDrawable(p.icon) }, FrameLayout.LayoutParams(dpi(ICON_DP), dpi(ICON_DP), Gravity.CENTER))
        return t
    }

    /** Apps whose name matches what's typed, up to five, best first. */
    private fun showApps(q: String) {
        val needle = q.trim().lowercase()
        val matches = if (needle.isEmpty()) {
            emptyList()
        } else {
            apps.mapNotNull { a ->
                val score = when {
                    a.lower.startsWith(needle) -> 0
                    a.lower.split(' ', '-', '.').any { it.startsWith(needle) } -> 1
                    needle.length > 1 && a.lower.contains(needle) -> 2
                    else -> return@mapNotNull null
                }
                score to a
            }.sortedWith(compareBy({ it.first }, { it.second.lower })).take(MAX_APPS).map { it.second }
        }
        appsRow.removeAllViews()
        if (matches.isEmpty()) {
            appsRow.visibility = View.GONE
            return
        }
        for (a in matches) appsRow.addView(appItem(a), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        // Keeps the five-column spacing with fewer matches.
        repeat(MAX_APPS - matches.size) { appsRow.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f)) }
        val appeared = appsRow.visibility != View.VISIBLE
        appsRow.visibility = View.VISIBLE
        if (appeared) staggerIn(appsRow, startDelay = 40)
    }

    /** A matching app: just its icon (long-press for its name). */
    private fun appItem(a: AppEntry): View {
        val item = FrameLayout(ctx).apply {
            setPadding(0, dpi(6), 0, dpi(6))
            background = RippleDrawable(ColorStateList.valueOf(0x26FFFFFF), null, squircle(dp(16f), Color.WHITE))
            contentDescription = a.label
            tooltipText = a.label
            setOnClickListener { launch(a) }
            pressable(this)
        }
        val icon = a.icon ?: runCatching { SearchPlaces.round(a.info.loadIcon(pm)) }.getOrNull().also { a.icon = it }
        item.addView(ImageView(ctx).apply { setImageDrawable(icon) }, FrameLayout.LayoutParams(dpi(46), dpi(46), Gravity.CENTER))
        return item
    }

    private fun launch(a: AppEntry) {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(a.component)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        try {
            service.startActivity(intent)
            close()
        } catch (_: Exception) {
            Toast.makeText(service, "Couldn't open ${a.label}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun focusInput() {
        input.requestFocus()
        input.setSelection(input.text.length)
        input.post { imm?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT) }
    }

    private fun hideKeyboard() {
        val r = root ?: return
        imm?.hideSoftInputFromWindow(r.windowToken, 0)
    }

    /** The panel sits just above the keyboard, following it as it slides. */
    private fun followKeyboard(ime: Int) {
        if (root == null) return
        val base = dp(BOTTOM_DP.toFloat())
        val lift = max(0f, ime + dp(10f) - base)
        searchHolder.translationY = -lift
    }

    // ---- Search → card ----------------------------------------------------------

    private fun showResult(p: SearchPlace) {
        if (mode != Mode.SEARCH || closing) return
        provider = p
        query = input.text.toString().trim()
        headerIcon.setImageDrawable(p.icon)
        headerTitle.text = query.ifBlank { p.label }
        openButton.visibility = if (p.private) View.GONE else View.VISIBLE
        if (p.private != privateMode) swapWeb(p.private)
        web?.loadUrl(p.url(query))
        input.clearFocus()
        hideKeyboard()
        mode = Mode.CARD
        layoutCard(ime = 0) // The keyboard is on its way down.

        transition?.cancel()
        searchCard.animate().alpha(0f).scaleX(0.96f).scaleY(0.96f).setDuration(160)
            .setInterpolator(EMPHASIZED_ACCELERATE)
            .withEndAction { if (mode != Mode.SEARCH) searchHolder.visibility = View.GONE }
            .start()

        result.visibility = View.VISIBLE
        result.alpha = 0f
        result.scaleX = 0.9f
        result.scaleY = 0.9f
        result.translationY = dp(64f)
        result.animate().alpha(1f).setDuration(200).setStartDelay(40).start()
        result.animate().scaleX(1f).scaleY(1f).translationY(0f)
            .setDuration(480).setStartDelay(0)
            .setInterpolator(EMPHASIZED_DECELERATE)
            .start()
        fullButton.setImageResource(R.drawable.ic_web_fullscreen)
        fullButton.contentDescription = "Full screen"
    }

    /** Back from the card to the panel, to change the query or pick somewhere else. */
    private fun editQuery() {
        if (mode != Mode.CARD || closing) return
        mode = Mode.SEARCH
        result.animate().cancel()
        result.pivotX = result.width / 2f
        result.pivotY = result.height.toFloat()
        result.animate().alpha(0f).scaleX(0.94f).scaleY(0.94f).translationY(dp(48f))
            .setDuration(200).setInterpolator(EMPHASIZED_ACCELERATE)
            .withEndAction { if (mode == Mode.SEARCH) result.visibility = View.GONE }
            .start()
        searchHolder.visibility = View.VISIBLE
        input.setText(query)
        searchCard.animate().cancel()
        searchCard.alpha = 0f
        searchCard.scaleX = 0.94f
        searchCard.scaleY = 0.94f
        searchCard.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(320)
            .setInterpolator(EMPHASIZED_DECELERATE).start()
        focusInput()
    }

    // ---- Card layout ------------------------------------------------------------

    private fun rootSize(): Pair<Float, Float> {
        val r = root
        if (r != null && r.width > 0) return r.width.toFloat() to r.height.toFloat()
        val b = if (Build.VERSION.SDK_INT >= 30) wm.currentWindowMetrics.bounds else null
        return if (b != null) {
            b.width().toFloat() to b.height().toFloat()
        } else {
            service.resources.displayMetrics.let { it.widthPixels.toFloat() to it.heightPixels.toFloat() }
        }
    }

    /** Where the card sits: low on the screen, over the app, clear of the keyboard. */
    private fun cardRect(ime: Int = imeBottom): RectF {
        val (w, h) = rootSize()
        val width = min(w - 2 * dp(SIDE_DP.toFloat()), dp(MAX_CARD_WIDTH_DP))
        val left = (w - width) / 2
        val bottom = h - max(dp(BOTTOM_DP.toFloat()), ime + dp(10f))
        val top = max(statusBarHeight() + dp(10f), bottom - h * CARD_HEIGHT)
        return RectF(left, top, left + width, bottom)
    }

    private fun layoutCard(ime: Int = imeBottom) {
        val rect = cardRect(ime)
        val lp = result.layoutParams as FrameLayout.LayoutParams
        lp.width = rect.width().toInt()
        lp.height = rect.height().toInt()
        lp.leftMargin = rect.left.toInt()
        lp.topMargin = rect.top.toInt()
        result.layoutParams = lp
        setHeaderTop(0)
        webBox.setPadding(0, 0, 0, 0)
        clip.set(0f, 0f, lp.width.toFloat(), lp.height.toFloat())
        clipRadius = dp(CORNER_DP)
        result.invalidateOutline()
        result.pivotX = rect.width() / 2
        result.pivotY = rect.height()
    }

    private fun layoutFull() {
        val (w, h) = rootSize()
        val lp = result.layoutParams as FrameLayout.LayoutParams
        lp.width = w.toInt()
        lp.height = h.toInt()
        lp.leftMargin = 0
        lp.topMargin = 0
        result.layoutParams = lp
        setHeaderTop(statusBarHeight())
        webBox.setPadding(0, 0, 0, imeBottom)
        clip.set(0f, 0f, w, h)
        clipRadius = 0f
        result.invalidateOutline()
    }

    /** In full screen the header reaches up under the status bar / camera. */
    private fun setHeaderTop(top: Int) {
        handle.visibility = if (top > 0) View.INVISIBLE else View.VISIBLE
        header.setPadding(header.paddingLeft, top, header.paddingRight, 0)
        val lp = header.layoutParams
        lp.height = dpi(HEADER_DP) + top
        header.layoutParams = lp
    }

    // ---- Full screen ------------------------------------------------------------

    private fun toggleFull() = when (mode) {
        Mode.CARD -> animateFull(enter = true)
        Mode.FULL -> animateFull(enter = false)
        else -> {}
    }

    /**
     * Card ↔ full screen. The card is laid out full size once at the start
     * (or card size once at the end), and in between only its clip and
     * position move: the clip grows from the card's rectangle to the screen
     * while the content slides up with it, so the page is never resized
     * mid-animation.
     */
    private fun animateFull(enter: Boolean) {
        if (transition != null || closing) return
        result.animate().cancel()
        result.scaleX = 1f
        result.scaleY = 1f
        result.alpha = 1f
        val card = cardRect()
        val (w, h) = rootSize()
        val status = statusBarHeight().toFloat()
        val dragOffset = result.translationY
        val cardRadius = dp(CORNER_DP)

        if (enter) {
            mode = Mode.FULL
            layoutFull()
        }
        fullButton.setImageResource(if (enter) R.drawable.ic_web_exit_fullscreen else R.drawable.ic_web_fullscreen)
        fullButton.contentDescription = if (enter) "Exit full screen" else "Full screen"

        fun apply(t: Float) {
            val l = lerp(card.left, 0f, t)
            val top = lerp(card.top, 0f, t)
            val rt = lerp(card.right, w, t)
            val b = lerp(card.bottom, h, t)
            val clipTop = status * (1 - t)
            val drag = dragOffset * (if (enter) 1 - t else t)
            result.translationY = top - clipTop + drag
            clip.set(l, clipTop, rt, clipTop + (b - top))
            clipRadius = lerp(cardRadius, 0f, t)
            result.invalidateOutline()
        }
        apply(if (enter) 0f else 1f)

        val a = ValueAnimator.ofFloat(if (enter) 0f else 1f, if (enter) 1f else 0f).apply {
            duration = if (enter) 440 else 380
            interpolator = if (enter) EMPHASIZED_DECELERATE else EMPHASIZED
            addUpdateListener { apply(it.animatedValue as Float) }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    transition = null
                    result.translationY = 0f
                    if (enter) {
                        layoutFull()
                    } else {
                        mode = Mode.CARD
                        layoutCard()
                    }
                }
            })
        }
        transition = a
        a.start()
    }

    /**
     * Header gestures: tap the query to change it; on the card, swipe up for
     * full screen or down to put it away; in full screen, swipe down to go
     * back to the card.
     */
    private inner class HeaderDrag : View.OnTouchListener {
        private val slop = ViewConfiguration.get(service).scaledTouchSlop
        private var downY = 0f
        private var dragging = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(v: View, e: MotionEvent): Boolean {
            if (transition != null) return true
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = e.rawY
                    dragging = false
                    result.animate().cancel()
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = e.rawY - downY
                    if (!dragging && abs(dy) > slop) dragging = true
                    if (dragging) {
                        result.translationY = when {
                            mode == Mode.CARD && dy > 0 -> dy
                            else -> dy * 0.25f // Resists: pulls a little, then lets go into the next state.
                        }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    val dy = e.rawY - downY
                    when {
                        !dragging -> {
                            v.performClick()
                            if (mode == Mode.CARD) editQuery()
                        }
                        mode == Mode.CARD && dy > dp(110f) -> close()
                        mode == Mode.CARD && dy < -dp(56f) -> animateFull(enter = true)
                        mode == Mode.FULL && dy > dp(64f) -> animateFull(enter = false)
                        else -> settle()
                    }
                }
                MotionEvent.ACTION_CANCEL -> settle()
            }
            return true
        }

        private fun settle() {
            result.animate().translationY(0f).setDuration(320).setInterpolator(OvershootInterpolator(1.1f)).start()
        }
    }

    // ---- Back -------------------------------------------------------------------

    private fun back() {
        when (mode) {
            Mode.SEARCH -> close()
            Mode.CARD -> if (web?.canGoBack() == true) web?.goBack() else editQuery()
            Mode.FULL -> when {
                videoView != null -> web?.webChromeClient?.onHideCustomView()
                web?.canGoBack() == true -> web?.goBack()
                else -> animateFull(enter = false)
            }
            Mode.CLOSED -> {}
        }
    }

    private fun watchBack(r: View) {
        if (Build.VERSION.SDK_INT >= 33) {
            r.post {
                val dispatcher = r.findOnBackInvokedDispatcher() ?: return@post
                val cb = OnBackInvokedCallback { back() }
                dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, cb)
                backCallback = cb
            }
        }
    }

    private fun unwatchBack(r: View) {
        if (Build.VERSION.SDK_INT >= 33) {
            (backCallback as? OnBackInvokedCallback)?.let { r.findOnBackInvokedDispatcher()?.unregisterOnBackInvokedCallback(it) }
        }
        backCallback = null
    }

    // ---- Open in the app --------------------------------------------------------

    /** The same search in the provider's own app (or the browser), closing the card. */
    private fun openInApp() {
        val p = provider ?: return
        val url = web?.url?.takeIf { it.startsWith("http") } ?: p.url(query)
        val tries = buildList {
            p.pkg?.let { add(Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(it)) }
            if (p.pkg != null && query.isNotBlank()) {
                add(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, query).setPackage(p.pkg))
            }
            p.pkg?.let { pm.getLaunchIntentForPackage(it) }?.takeIf { query.isBlank() }?.let { add(it) }
            add(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
        for (intent in tries) {
            if (intent.resolveActivity(pm) == null) continue
            try {
                service.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                close()
                return
            } catch (_: Exception) {
            }
        }
        Toast.makeText(service, "Couldn't open ${p.label}", Toast.LENGTH_SHORT).show()
    }

    /** A link the page hands to another app (tel:, upi:, a Play Store page…). */
    private fun startOutside(intent: Intent) {
        try {
            service.startActivity(intent.addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            close()
        } catch (_: ActivityNotFoundException) {
        }
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            return when (uri.scheme?.lowercase()) {
                "http", "https", "about", "data", "blob", "javascript" -> false
                "intent" -> {
                    try {
                        val intent = Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME).setComponent(null)
                        intent.selector = null
                        if (intent.resolveActivity(pm) != null) {
                            startOutside(intent)
                        } else {
                            intent.getStringExtra("browser_fallback_url")?.let { view.loadUrl(it) }
                        }
                    } catch (_: Exception) {
                    }
                    true
                }
                else -> {
                    // Only on a tap: pages also try app links on their own as they load.
                    if (request.hasGesture()) startOutside(Intent(Intent.ACTION_VIEW, uri))
                    true
                }
            }
        }
    }

    /** Progress, video full screen, and the page's pop-ups (there's no screen here to show a dialog on). */
    private inner class Chrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress?.progress = newProgress
            progress?.visibility = if (newProgress < 100) View.VISIBLE else View.GONE
        }

        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            val r = root
            if (videoView != null || r == null) return callback.onCustomViewHidden()
            videoView = view
            videoCallback = callback
            view.setBackgroundColor(Color.BLACK)
            r.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }

        override fun onHideCustomView() {
            val v = videoView ?: return
            root?.removeView(v)
            videoView = null
            videoCallback?.onCustomViewHidden()
            videoCallback = null
        }

        override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            if (!message.isNullOrBlank()) Toast.makeText(service, message, Toast.LENGTH_LONG).show()
            result.confirm()
            return true
        }

        override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            result.cancel()
            return true
        }

        override fun onJsPrompt(view: WebView, url: String?, message: String?, defaultValue: String?, result: JsPromptResult): Boolean {
            result.cancel()
            return true
        }

        override fun onJsBeforeUnload(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            result.confirm()
            return true
        }
    }

    // ---- Providers & apps -------------------------------------------------------

    /** The bar's places, as chosen in the launcher's settings. */
    private fun loadProviders(): List<SearchPlace> = SearchPlaces.shown(service)

    private fun isInstalled(pkg: String) = try {
        pm.getApplicationInfo(pkg, 0).enabled
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    /** The home screen's apps (hidden ones left out), read off the main thread now and then. */
    private fun loadAppsIfStale() {
        val now = System.currentTimeMillis()
        if (apps.isNotEmpty() && now - appsAt < 5 * 60_000) return
        appsAt = now
        Thread {
            val hidden = hiddenIds()
            val list = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
                .asSequence()
                .filter { it.activityInfo.packageName != service.packageName }
                .filter { "${it.activityInfo.packageName}/${it.activityInfo.name}" !in hidden }
                .map {
                    val label = it.loadLabel(pm).toString()
                    AppEntry(label, label.lowercase(), ComponentName(it.activityInfo.packageName, it.activityInfo.name), it)
                }
                .toList()
            main.post {
                apps = list
                if (mode == Mode.SEARCH && root != null) showApps(input.text.toString())
            }
        }.start()
    }

    /** The launcher's hidden apps, as the Flutter side keeps them ("package/activity" ids). */
    private fun hiddenIds(): Set<String> = try {
        when (val raw = service.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).all["flutter.hidden_app_ids"]) {
            is String -> {
                val a = JSONArray(raw.substring(raw.indexOf('!') + 1))
                (0 until a.length()).map { a.getString(it) }.toSet()
            }
            is Set<*> -> raw.filterIsInstance<String>().toSet()
            else -> emptySet()
        }
    } catch (_: Exception) {
        emptySet()
    }

    // ---- Small helpers ----------------------------------------------------------

    private fun prefs() = service.getSharedPreferences("browser_button", Context.MODE_PRIVATE)

    /** The tiles' and pill's look: a faint fill with a hairline edge. */
    private fun squircle(radius: Float, fill: Int) = GradientDrawable().apply {
        cornerRadius = radius
        setColor(fill)
        setStroke(max(1, dpi(0.5f)), 0x1FFFFFFF)
    }

    /**
     * Takes the screen as it is (when a hold begins, so it's ready when the
     * panel opens) for the frosted backdrop. Only drawn, blurred, behind the
     * panel; dropped when it closes.
     */
    private fun captureBackdrop() {
        if (Build.VERSION.SDK_INT < 31) return
        try {
            service.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                service.mainExecutor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(shot: AccessibilityService.ScreenshotResult) {
                        val buffer = shot.hardwareBuffer
                        val bitmap = Bitmap.wrapHardwareBuffer(buffer, shot.colorSpace)
                        buffer.close()
                        backdrop = bitmap
                        backdropAt = SystemClock.uptimeMillis()
                        if (mode != Mode.CLOSED && !closing && root != null) showBackdrop()
                    }

                    override fun onFailure(errorCode: Int) {}
                },
            )
        } catch (_: Exception) {
        }
    }

    /** Fades the frosted screen in behind the panel (if it was taken just now). */
    private fun showBackdrop() {
        val b = backdrop ?: return
        if (SystemClock.uptimeMillis() - backdropAt > 3_000 || backdropView.drawable != null) return
        backdropView.setImageBitmap(b)
        backdropView.animate().alpha(1f).setDuration(240).setInterpolator(STANDARD).start()
        searchCard.background = panelBackground(dp(PANEL_CORNER_DP))
        if (scrim.alpha > GLASS_SCRIM_ALPHA) scrim.animate().alpha(GLASS_SCRIM_ALPHA).setDuration(240).start()
    }

    /** Sinks a little under the finger and springs back. */
    @SuppressLint("ClickableViewAccessibility")
    private fun pressable(v: View) {
        v.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN ->
                    v.animate().scaleX(0.9f).scaleY(0.9f).setDuration(90).setInterpolator(STANDARD).start()
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    v.animate().scaleX(1f).scaleY(1f).setDuration(260).setInterpolator(OvershootInterpolator(2.4f)).start()
            }
            false
        }
    }

    /** The row's items rise in one after another. */
    private fun staggerIn(row: ViewGroup, startDelay: Long) {
        for (i in 0 until row.childCount) {
            val c = row.getChildAt(i)
            c.alpha = 0f
            c.translationY = dp(10f)
            c.animate().alpha(1f).translationY(0f)
                .setStartDelay(startDelay + i * 28L)
                .setDuration(300)
                .setInterpolator(EMPHASIZED_DECELERATE)
                .start()
        }
    }

    /**
     * Puts the panel away, then opens Google's Circle to Search over the app
     * (after the panel is gone, so it's the app that gets circled).
     */
    private fun circleToSearch() {
        close()
        main.postDelayed({
            Thread {
                val direct = CircleToSearch.start()
                if (direct == null) return@Thread
                val viaShizuku = try {
                    if (!rikka.shizuku.Shizuku.pingBinder() ||
                        rikka.shizuku.Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED
                    ) {
                        "Shizuku isn't running"
                    } else {
                        com.arun.minimal_launcher.privileged.PrivilegedServiceClient.shared(service).get(5_000).startCircleToSearch()
                    }
                } catch (e: Exception) {
                    e.message ?: e.javaClass.simpleName
                }
                if (viaShizuku != null) {
                    android.util.Log.w("QuickSearch", "Circle to Search: $direct / $viaShizuku")
                    main.post { Toast.makeText(service, "Couldn't open Circle to Search ($viaShizuku)", Toast.LENGTH_LONG).show() }
                }
            }.start()
        }, CTS_DELAY_MS)
    }

    private fun panelBackground(radius: Float) = GradientDrawable().apply {
        cornerRadius = radius
        // Translucent over the frosted backdrop (near-solid when there's none).
        setColor(if (backdrop != null && Build.VERSION.SDK_INT >= 31) 0xA6121212.toInt() else 0xF2111111.toInt())
        setStroke(max(1, dpi(0.5f)), 0x26FFFFFF)
    }

    private fun icon(res: Int, tint: Int) = ImageView(ctx).apply {
        setImageResource(res)
        imageTintList = ColorStateList.valueOf(tint)
    }

    private fun iconButton(res: Int, label: String, tint: Int, onClick: () -> Unit) = icon(res, tint).apply {
        setPadding(dpi(10), dpi(10), dpi(10), dpi(10))
        contentDescription = label
        background = RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), null, GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
        })
        setOnClickListener { onClick() }
    }

    private fun imeOf(insets: WindowInsets): Int =
        if (Build.VERSION.SDK_INT >= 30) insets.getInsets(WindowInsets.Type.ime()).bottom else 0

    @SuppressLint("InternalInsetResource", "DiscouragedApi")
    private fun statusBarHeight(): Int {
        val id = service.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) service.resources.getDimensionPixelSize(id) else dpi(28)
    }

    private fun dp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, service.resources.displayMetrics)
    private fun dpi(v: Int) = dp(v.toFloat()).toInt()
    private fun dpi(v: Float) = dp(v).toInt()
    private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

    companion object {
        private const val INCOGNITO_PROFILE = "quick_search_incognito"

        /** The touch strip along the bottom centre: about the home-gesture area. */
        private const val STRIP_WIDTH_DP = 150
        private const val STRIP_HEIGHT_DP = 20

        /** Hold this long (after a short pause that ignores swipes) to open. */
        private const val HOLD_DELAY_MS = 70L
        private const val HOLD_MS = 330L

        private const val SIDE_DP = 10
        private const val BOTTOM_DP = 26
        private const val CORNER_DP = 26f
        /** Panel radius = tile radius + the panel's padding, so the corners nest evenly. */
        private const val PANEL_CORNER_DP = 38f
        private const val HEADER_DP = 58
        private const val TILE_DP = 56
        private const val ICON_DP = 48
        private const val PILL_DP = 52
        private const val GOOGLE_APP = "com.google.android.googlequicksearchbox"
        private const val MAX_CARD_WIDTH_DP = 600f
        private const val CARD_HEIGHT = 0.66f
        private const val SCRIM_ALPHA = 0.35f

        /** Lighter dim over the frosted backdrop, and its blur. */
        private const val GLASS_SCRIM_ALPHA = 0.18f
        private const val BLUR_DP = 28f
        private const val MAX_APPS = 5

        /** Waits for the panel to be gone before Circle to Search takes its screenshot. */
        private const val CTS_DELAY_MS = 320L

        // Material 3 motion curves.
        private val EMPHASIZED = PathInterpolator(0.2f, 0f, 0f, 1f)
        private val EMPHASIZED_DECELERATE = PathInterpolator(0.05f, 0.7f, 0.1f, 1f)
        private val EMPHASIZED_ACCELERATE = PathInterpolator(0.3f, 0f, 0.8f, 0.15f)
        private val STANDARD = PathInterpolator(0.2f, 0f, 0f, 1f)

    }
}
