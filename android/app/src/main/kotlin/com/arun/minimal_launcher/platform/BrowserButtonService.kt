package com.arun.minimal_launcher.platform

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.app.DownloadManager
import android.app.KeyguardManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.arun.minimal_launcher.R
import kotlin.math.abs

/**
 * "Full-screen button" (a settings switch): a small round button floating
 * on the right edge whenever a web browser is on screen.
 *
 * Tap it and the page that browser shows covers the whole screen, address
 * bar, status bar and navigation bar included; tap it again (or go back
 * past the first page) and the browser is right there as it was. The page
 * is a layer over the browser, never another screen, so nothing else opens
 * or animates in between (and an app-locked browser isn't asked to unlock
 * again). Leaving the browser (home, another app, locking) closes it.
 * Drag the button up or down to move it; where it was left is remembered.
 *
 * Android only lets an accessibility service draw over other apps this way
 * and read the browser's address bar; nothing else on screen is read or
 * kept. Turned on from the launcher's settings (directly when the launcher
 * holds WRITE_SECURE_SETTINGS, else in Android's accessibility settings).
 */
class BrowserButtonService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private var button: ImageView? = null
    private var buttonParams: WindowManager.LayoutParams? = null

    /** The browser the button is showing over, whose address it reads. */
    private var browser: String? = null

    private var browsers: Set<String> = emptySet()
    private var browsersAt = 0L

    // ---- The full-screen page ----
    private var page: FrameLayout? = null
    private var web: WebView? = null
    private var progress: ProgressBar? = null

    /** The browser address the page was opened from: tapping again on the same one just shows it. */
    private var pageFrom: String? = null
    private var pageShown = false

    /** The thin frosted strip along the top of the page, over where the status bar was. */
    private var topBlur: View? = null
    private var backCallback: Any? = null
    private var videoView: View? = null
    private var videoCallback: WebChromeClient.CustomViewCallback? = null

    /** "Hold to search" over any app (its own switch; see [QuickSearchOverlay]). */
    private var quickSearch: QuickSearchOverlay? = null

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            hideAll()
            quickSearch?.update(on = false, locked = true, keyboard = false)
        }
    }

    /** Either switch flipped in the launcher's settings. */
    private val prefsChanged = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == KEY_BUTTON || key == KEY_HOLD_SEARCH) main.post { update() }
    }

    override fun onServiceConnected() {
        prefs().edit().putBoolean(KEY_WANTED, true).apply()
        wm = getSystemService(WindowManager::class.java)
        quickSearch = QuickSearchOverlay(this) { update() }
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        prefs().registerOnSharedPreferenceChangeListener(prefsChanged)
        update()
    }

    /** Switched off in Android's settings (an update just stops the process, without this). */
    override fun onUnbind(intent: Intent?): Boolean {
        prefs().edit().putBoolean(KEY_WANTED, false).apply()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(screenOff) }
        prefs().unregisterOnSharedPreferenceChangeListener(prefsChanged)
        quickSearch?.destroy()
        quickSearch = null
        hideAll()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) activityOf(event)?.let { quickSearch?.onAppSwitched(it) }
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> update()
        }
    }

    // ---- When to show ---------------------------------------------------------

    /** The package whose screen (an activity) [event] brought to the front; null for dialogs, panels, overlays. */
    private fun activityOf(event: AccessibilityEvent): String? {
        val pkg = event.packageName?.toString() ?: return null
        val cls = event.className?.toString() ?: return null
        return try {
            packageManager.getActivityInfo(ComponentName(pkg, cls), 0)
            pkg
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    /** The button over a browser in front; everything closed otherwise (and on the lock screen). */
    private fun update() {
        val locked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        val app = frontApp()
        quickSearch?.update(
            on = prefs().getBoolean(KEY_HOLD_SEARCH, false),
            locked = locked,
            keyboard = windows.any { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD },
        )
        if (locked || !prefs().getBoolean(KEY_BUTTON, true)) return hideAll()
        if (app == null) return // Only system windows changed (shade, keyboard): keep as is.
        if (app != packageName && app in browsers()) {
            if (app != browser) closePage(destroy = true)
            showButton(app)
        } else {
            hideAll()
        }
    }

    /** The package of the app window in front, null if there isn't one. */
    private fun frontApp(): String? {
        val apps = windows.filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
        // While the page is up it has the focus, so the browser under it is just the top app window.
        val front = apps.firstOrNull { it.isFocused } ?: apps.firstOrNull { it.isActive } ?: apps.firstOrNull()
            ?: return null
        return front.root?.packageName?.toString()
    }

    /** Apps that open any web page, refreshed now and then (browsers get installed). */
    private fun browsers(): Set<String> {
        val now = System.currentTimeMillis()
        if (now - browsersAt > 60_000 || browsers.isEmpty()) {
            browsers = packageManager
                .queryIntentActivities(
                    Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")).addCategory(Intent.CATEGORY_BROWSABLE),
                    PackageManager.MATCH_ALL,
                )
                .map { it.activityInfo.packageName }
                .toSet() - imePackages()
            browsersAt = now
        }
        return browsers
    }

    private fun imePackages(): Set<String> =
        getSystemService(InputMethodManager::class.java)?.enabledInputMethodList?.map { it.packageName }?.toSet()
            ?: emptySet()

    private fun hideAll() {
        closePage(destroy = true)
        hideButton()
    }

    // ---- The button -----------------------------------------------------------

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun showButton(pkg: String) {
        browser = pkg
        if (button != null) return
        warmUpWebView()
        val size = dp(44)
        val p = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.END or Gravity.TOP
            x = dp(6)
            y = prefs().getInt(KEY_Y, resources.displayMetrics.heightPixels / 2 - size / 2)
        }
        val b = ImageView(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xB3000000.toInt())
                setStroke(dp(1), 0x40FFFFFF)
            }
            setPadding(dp(11), dp(11), dp(11), dp(11))
            alpha = IDLE_ALPHA
            setOnTouchListener(Dragger(p))
        }
        try {
            wm.addView(b, p)
            button = b
            buttonParams = p
            refreshButton()
        } catch (_: Exception) {
        }
    }

    private fun hideButton() {
        val b = button ?: return
        runCatching { wm.removeView(b) }
        button = null
        buttonParams = null
    }

    private fun refreshButton() {
        button?.apply {
            setImageResource(if (pageShown) R.drawable.ic_web_exit_fullscreen else R.drawable.ic_web_fullscreen)
            contentDescription = if (pageShown) "Back to the browser" else "View this page full screen"
        }
    }

    /** Keeps the button above the page (windows stack in the order they're added). */
    private fun raiseButton() {
        val b = button ?: return
        val p = buttonParams ?: return
        runCatching { wm.removeView(b) }
        runCatching { wm.addView(b, p) }
    }

    /** Drags the button up and down; a tap (no drag) switches full screen on or off. */
    private inner class Dragger(private val p: WindowManager.LayoutParams) : View.OnTouchListener {
        private val slop = ViewConfiguration.get(this@BrowserButtonService).scaledTouchSlop
        private var downY = 0f
        private var startY = 0
        private var dragging = false

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = e.rawY
                    startY = p.y
                    dragging = false
                    v.alpha = PRESSED_ALPHA
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = e.rawY - downY
                    if (!dragging && abs(dy) > slop) dragging = true
                    if (dragging) {
                        val max = resources.displayMetrics.heightPixels - p.height
                        p.y = (startY + dy.toInt()).coerceIn(0, max)
                        runCatching { wm.updateViewLayout(v, p) }
                    }
                }
                MotionEvent.ACTION_UP -> {
                    v.alpha = IDLE_ALPHA
                    if (dragging) {
                        prefs().edit().putInt(KEY_Y, p.y).apply()
                    } else {
                        v.performClick()
                        if (pageShown) closePage(destroy = false) else openPage()
                    }
                }
                MotionEvent.ACTION_CANCEL -> v.alpha = IDLE_ALPHA
            }
            return true
        }
    }

    // ---- Opening and closing the page ---------------------------------------------

    private fun openPage() {
        val url = currentUrl()
        if (url == null) {
            Toast.makeText(this, "Couldn't read this page's address. Scroll up so it shows, then try again", Toast.LENGTH_SHORT).show()
            return
        }
        val root = page ?: buildPage()
        val view = web ?: return
        if (url != pageFrom) {
            pageFrom = url
            view.loadUrl(url)
        }
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.OPAQUE,
        ).apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            windowAnimations = 0
        }
        try {
            wm.addView(root, p)
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't show the page", e)
            return
        }
        pageShown = true
        view.onResume()
        view.requestFocus()
        watchBack(root)
        showTopBlur()
        raiseButton()
        quickSearch?.raise()
        refreshButton()
    }

    /**
     * Back to the browser. [destroy]: also drop the page (the browser was
     * left); else it's kept, paused, so the next tap on the same page shows
     * it again at once.
     */
    private fun closePage(destroy: Boolean) {
        val root = page
        if (pageShown && root != null) {
            videoView?.let { web?.webChromeClient?.onHideCustomView() }
            unwatchBack(root)
            hideKeyboard(root)
            hideTopBlur()
            runCatching { wm.removeView(root) }
            pageShown = false
            web?.evaluateJavascript("document.querySelectorAll('video,audio').forEach(function(m){m.pause()})", null)
            web?.onPause()
            CookieManager.getInstance().flush()
            refreshButton()
        }
        if (destroy && root != null) {
            web?.destroy()
            web = null
            page = null
            progress = null
            pageFrom = null
        }
    }

    /**
     * A small frosted strip along the top edge, as tall as the status bar
     * was, so the page softens under the camera instead of being cut off.
     * Real blur of the page behind when the phone allows it (Android 12+,
     * blur on, not in battery saver), else a soft dark fade.
     */
    private fun showTopBlur() {
        if (topBlur != null) return
        val height = statusBarHeight()
        val strip = View(this)
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            height,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
            windowAnimations = 0
        }
        try {
            wm.addView(strip, p)
        } catch (_: Exception) {
            return
        }
        strip.background = blurDrawable(strip) ?: GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0x99000000.toInt(), 0x00000000),
        )
        topBlur = strip
    }

    private fun hideTopBlur() {
        val strip = topBlur ?: return
        runCatching { wm.removeView(strip) }
        topBlur = null
    }

    /** Android's own frosted-glass drawable for [view]'s window (what Window.setBackgroundBlurRadius uses); null if unavailable. */
    private fun blurDrawable(view: View): android.graphics.drawable.Drawable? {
        if (Build.VERSION.SDK_INT < 31 || !wm.isCrossWindowBlurEnabled) return null
        return try {
            val root = org.lsposed.hiddenapibypass.HiddenApiBypass.invoke(View::class.java, view, "getViewRootImpl") ?: return null
            val d = org.lsposed.hiddenapibypass.HiddenApiBypass.invoke(root.javaClass, root, "createBackgroundBlurDrawable")
                as android.graphics.drawable.Drawable
            org.lsposed.hiddenapibypass.HiddenApiBypass.invoke(d.javaClass, d, "setBlurRadius", dp(18))
            org.lsposed.hiddenapibypass.HiddenApiBypass.invoke(d.javaClass, d, "setColor", 0x33000000)
            d
        } catch (e: Throwable) {
            Log.w(TAG, "No window blur", e)
            null
        }
    }

    @SuppressLint("InternalInsetResource", "DiscouragedApi")
    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else dp(28)
    }

    private fun goBack() {
        when {
            videoView != null -> web?.webChromeClient?.onHideCustomView()
            web?.canGoBack() == true -> web?.goBack()
            else -> closePage(destroy = false)
        }
    }

    /** Back (gesture or key) goes back a page, and to the browser on the first. */
    private fun watchBack(root: View) {
        if (Build.VERSION.SDK_INT >= 33) {
            val dispatcher = root.findOnBackInvokedDispatcher() ?: return
            val cb = OnBackInvokedCallback { goBack() }
            dispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, cb)
            backCallback = cb
        }
    }

    private fun unwatchBack(root: View) {
        if (Build.VERSION.SDK_INT >= 33) {
            (backCallback as? OnBackInvokedCallback)?.let { root.findOnBackInvokedDispatcher()?.unregisterOnBackInvokedCallback(it) }
        }
        backCallback = null
    }

    private fun hideKeyboard(v: View) {
        getSystemService(InputMethodManager::class.java)?.hideSoftInputFromWindow(v.windowToken, 0)
    }

    private var warmedUp = false

    /** Loads the web engine once ahead of time, so the first tap opens the page without a pause. */
    private fun warmUpWebView() {
        if (warmedUp) return
        warmedUp = true
        guardMainLooper()
        main.post { runCatching { WebSettings.getDefaultUserAgent(this) } }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun buildPage(): FrameLayout {
        val ctx = ContextThemeWrapper(this, android.R.style.Theme_DeviceDefault)
        val root = object : FrameLayout(ctx) {
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                    if (event.action == KeyEvent.ACTION_UP) goBack()
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        root.setBackgroundColor(Color.BLACK)
        // Room for the keyboard.
        root.setOnApplyWindowInsetsListener { v, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= 30) insets.getInsets(WindowInsets.Type.ime()).bottom else 0
            v.setPadding(0, 0, 0, bottom)
            insets
        }

        val view = WebView(ctx).apply {
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
                setSupportMultipleWindows(false) // target=_blank opens here
                // Look like Chrome, not an in-app WebView: some sites (Google
                // sign-in among them) refuse WebViews by their user agent.
                userAgentString = userAgentString
                    .replace("; wv)", ")")
                    .replace(Regex("Version/\\S+ "), "")
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            webViewClient = PageClient()
            webChromeClient = PageChrome()
            setDownloadListener { url, userAgent, disposition, mime, _ -> download(url, userAgent, disposition, mime) }
        }
        val bar = ProgressBar(ctx, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            visibility = View.GONE
        }
        root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(3), Gravity.TOP))
        page = root
        web = view
        progress = bar
        return root
    }

    private fun download(url: String, userAgent: String, disposition: String?, mime: String?) {
        try {
            val name = URLUtil.guessFileName(url, disposition, mime)
            val request = DownloadManager.Request(Uri.parse(url))
                .setMimeType(mime)
                .addRequestHeader("User-Agent", userAgent)
                .apply { CookieManager.getInstance().getCookie(url)?.let { addRequestHeader("Cookie", it) } }
                .setTitle(name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            getSystemService(DownloadManager::class.java).enqueue(request)
            Toast.makeText(this, "Downloading $name", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            Toast.makeText(this, "Couldn't download that", Toast.LENGTH_SHORT).show()
        }
    }

    /** Hands a link to another app (tel:, upi:, a Play Store page…), closing the page. */
    private fun startOutside(intent: Intent) {
        try {
            startActivity(intent.addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            closePage(destroy = false)
        } catch (_: ActivityNotFoundException) {
        }
    }

    private inner class PageClient : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            return when (uri.scheme?.lowercase()) {
                "http", "https", "about", "data", "blob", "javascript" -> false
                "intent" -> {
                    try {
                        val intent = Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME).setComponent(null)
                        intent.selector = null
                        if (intent.resolveActivity(packageManager) != null) {
                            startOutside(intent)
                        } else {
                            intent.getStringExtra("browser_fallback_url")?.let { view.loadUrl(it) }
                        }
                    } catch (_: Exception) {
                    }
                    true
                }
                else -> {
                    startOutside(Intent(Intent.ACTION_VIEW, uri))
                    true
                }
            }
        }
    }

    /**
     * Video full screen, progress, and the page's own pop-ups. A page here
     * has no screen of its own to put a dialog on, so alert / confirm /
     * prompt are answered without one (an alert's text shows as a toast).
     */
    private inner class PageChrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress?.progress = newProgress
            progress?.visibility = if (newProgress < 100) View.VISIBLE else View.GONE
        }

        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            val root = page
            if (videoView != null || root == null) return callback.onCustomViewHidden()
            videoView = view
            videoCallback = callback
            root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }

        override fun onHideCustomView() {
            val v = videoView ?: return
            page?.removeView(v)
            videoView = null
            videoCallback?.onCustomViewHidden()
            videoCallback = null
        }

        override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            if (!message.isNullOrBlank()) Toast.makeText(this@BrowserButtonService, message, Toast.LENGTH_LONG).show()
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

    // ---- Reading the address ---------------------------------------------------

    /** What the front browser's address bar says, as a full web address. */
    private fun currentUrl(): String? {
        val pkg = browser ?: return null
        val root = windows
            .filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
            .mapNotNull { it.root }
            .firstOrNull { it.packageName == pkg } ?: rootInActiveWindow ?: return null
        val text = urlBarIds.asSequence()
            .flatMap { root.findAccessibilityNodeInfosByViewId("$pkg:id/$it").asSequence() }
            .mapNotNull { it.text?.toString()?.trim() }
            .firstOrNull { it.isNotEmpty() && !it.contains(' ') }
            ?: return null
        return if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*://").containsMatchIn(text)) text else "https://$text"
    }

    private fun prefs() = getSharedPreferences("browser_button", Context.MODE_PRIVATE)

    companion object {
        private const val TAG = "BrowserButton"
        private const val KEY_Y = "y"
        private const val KEY_WANTED = "wanted"

        /** The two things this service does, each with its own switch. */
        private const val KEY_BUTTON = "button"
        private const val KEY_HOLD_SEARCH = "hold_search"

        /** Faded while resting, so it barely shows over the page; clear while touched. */
        private const val IDLE_ALPHA = 0.35f
        private const val PRESSED_ALPHA = 0.9f

        /** Address-bar view ids: Chrome & its family (Edge, Brave, Vivaldi…), Samsung, Firefox, Opera, DuckDuckGo, Kiwi. */
        private val urlBarIds = listOf(
            "url_bar",
            "location_bar_edit_text",
            "mozac_browser_toolbar_url_view",
            "url_field",
            "omnibarTextInput",
            "search_box",
        )

        private var guarded = false

        /**
         * A few page controls (a multi-choice list, a date picker) open an
         * Android dialog, which can't be shown from this layer (it isn't an
         * app screen) and would crash the whole launcher. This keeps the
         * main thread running past just that error, so the control simply
         * doesn't open.
         */
        internal fun guardMainLooper() {
            if (guarded) return
            guarded = true
            Handler(Looper.getMainLooper()).post {
                while (true) {
                    try {
                        Looper.loop()
                    } catch (e: WindowManager.BadTokenException) {
                        Log.w(TAG, "A page tried to open a dialog", e)
                    }
                }
            }
        }

        private fun component(context: Context) = ComponentName(context, BrowserButtonService::class.java).flattenToString()

        private fun enabledList(context: Context): List<String> =
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?.split(':')?.filter { it.isNotBlank() } ?: emptyList()

        private fun prefsOf(context: Context) = context.getSharedPreferences("browser_button", Context.MODE_PRIVATE)

        /** The full-screen button over browsers is on. */
        fun isButtonOn(context: Context) = isEnabled(context) && prefsOf(context).getBoolean(KEY_BUTTON, true)

        /** Hold-to-search (bottom centre, any app) is on. */
        fun isHoldSearchOn(context: Context) = isEnabled(context) && prefsOf(context).getBoolean(KEY_HOLD_SEARCH, false)

        fun setButton(context: Context, on: Boolean) = setFeature(context, KEY_BUTTON, on)

        fun setHoldSearch(context: Context, on: Boolean) = setFeature(context, KEY_HOLD_SEARCH, on)

        /**
         * Switches one feature; the service itself runs while either is on.
         * False if the service had to be turned on and the launcher can't
         * (open Android's accessibility settings then).
         */
        private fun setFeature(context: Context, key: String, on: Boolean): Boolean {
            val p = prefsOf(context)
            val running = isEnabled(context)
            val edit = p.edit().putBoolean(key, on)
            // Starting the service for this one: the other wasn't on.
            if (on && !running) edit.putBoolean(if (key == KEY_BUTTON) KEY_HOLD_SEARCH else KEY_BUTTON, false)
            edit.commit()
            val wanted = p.getBoolean(KEY_BUTTON, true) || p.getBoolean(KEY_HOLD_SEARCH, false)
            if (wanted == running) return true
            return setEnabled(context, wanted) || !on
        }

        fun isEnabled(context: Context): Boolean {
            val me = component(context)
            return enabledList(context).any { ComponentName.unflattenFromString(it)?.flattenToString() == me }
        }

        /**
         * Turns the service on or off itself; false if the launcher can't
         * (no WRITE_SECURE_SETTINGS), and the user must do it in Android's
         * accessibility settings.
         */
        fun setEnabled(context: Context, on: Boolean): Boolean {
            if (context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
            context.getSharedPreferences("browser_button", Context.MODE_PRIVATE).edit().putBoolean(KEY_WANTED, on).apply()
            val me = component(context)
            val others = enabledList(context).filter { ComponentName.unflattenFromString(it)?.flattenToString() != me }
            val list = if (on) others + me else others
            return try {
                val resolver = context.contentResolver
                Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, list.joinToString(":"))
                if (on) Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
                true
            } catch (_: SecurityException) {
                false
            }
        }

        /**
         * Android switches accessibility services off when their app is
         * updated: turned back on at start-up if it was on in settings.
         */
        fun restoreIfWanted(context: Context) {
            val wanted = context.getSharedPreferences("browser_button", Context.MODE_PRIVATE).getBoolean(KEY_WANTED, false)
            if (wanted && !isEnabled(context)) setEnabled(context, true)
        }

        fun openSettings(context: Context): Boolean = try {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }
}
