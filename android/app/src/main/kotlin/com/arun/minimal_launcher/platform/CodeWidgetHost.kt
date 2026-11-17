package com.arun.minimal_launcher.platform

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import org.xmlpull.v1.XmlPullParser
import java.util.Collections
import java.util.WeakHashMap

/**
 * An [AppWidgetHost] that can also show "code widgets": OriginOS (vivo / iQOO)
 * system widgets such as the clock, weather, music, gallery and notes. Their
 * layouts are built from custom View classes inside the widget's own app, not
 * RemoteViews, so Android's AppWidgetHostView refuses to inflate them and
 * shows "Can't load widget". vivo's own launcher instead loads the widget app's
 * code and inflates the layout itself; [CodeWidgetHostView] does the same.
 *
 * Only preinstalled system apps get this: a downloaded app's widget never runs
 * code inside the launcher. It changes nothing on the phone.
 */
class CodeWidgetHost(context: Context, hostId: Int) : AppWidgetHost(context, hostId) {

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    init {
        installCrashGuard()
    }

    override fun onCreateView(context: Context, appWidgetId: Int, appWidget: AppWidgetProviderInfo?): AppWidgetHostView =
        CodeWidgetHostView(context, ::allowsCode)

    /** Lets code widgets pause their clocks and animations while the home screen is hidden. */
    fun setVisible(visible: Boolean) {
        visibleNow = visible
        synchronized(live) { live.toList() }.forEach { it.onHostVisible(visible) }
    }

    private fun allowsCode(packageName: String): Boolean = packageName !in blocked()

    private fun blocked(): Set<String> = prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()

    /**
     * Code from a widget app runs on our main thread. If it ever crashes the
     * launcher, remember that app so its widgets are shown the standard way
     * from the next start (as vivo's launcher does), instead of crashing again.
     */
    private fun installCrashGuard() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous is CrashGuard) return
        Thread.setDefaultUncaughtExceptionHandler(CrashGuard(previous))
    }

    private inner class CrashGuard(private val next: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(t: Thread, e: Throwable) {
            runCatching {
                val culprit = codePackages.firstOrNull { pkg -> causedBy(t, e, pkg) }
                if (culprit != null) {
                    // commit(): the process is about to die.
                    prefs.edit().putStringSet(KEY_BLOCKED, blocked() + culprit).commit()
                }
            }
            next?.uncaughtException(t, e)
        }

        /**
         * Widget apps often crash in shared vivo libraries bundled in their APK
         * (e.g. com.bbk.widget.common.* inside com.vivo.devicepower), on a
         * thread they named after themselves. So match the thread name, the
         * package prefix, or any class that only the app's own code has.
         */
        private fun causedBy(t: Thread, e: Throwable, pkg: String): Boolean {
            if (pkg in t.name) return true
            val ours = CodeWidgetHost::class.java.classLoader
            val theirs = CodeWidgetHostView.codeLoaderOf(pkg)
            var cause: Throwable? = e
            var depth = 0
            while (cause != null && depth++ < 8) {
                if (cause.stackTrace.any { it.className.startsWith("$pkg.") || onlyIn(it.className, theirs, ours) }) {
                    return true
                }
                cause = cause.cause
            }
            return false
        }

        private fun onlyIn(className: String, theirs: ClassLoader?, ours: ClassLoader?): Boolean {
            if (theirs == null) return false
            fun loads(loader: ClassLoader?) = runCatching { Class.forName(className, false, loader) }.isSuccess
            return loads(theirs) && !loads(ours)
        }
    }

    companion object {
        private const val PREFS = "code_widgets"
        private const val KEY_BLOCKED = "blocked_packages"

        /** Every code widget showing now, so [setVisible] reaches them. */
        internal val live: MutableSet<CodeWidgetHostView> = Collections.newSetFromMap(WeakHashMap())

        /** Packages whose code we have loaded, for the crash guard. */
        internal val codePackages: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())

        @Volatile
        internal var visibleNow = true
    }
}

/**
 * An AppWidgetHostView that inflates a widget's layout with the widget app's
 * own code when it needs it (see [CodeWidgetHost]), then applies the widget's
 * RemoteViews updates to it. Ordinary widgets go through Android unchanged.
 */
class CodeWidgetHostView(
    context: Context,
    private val allowsCode: (packageName: String) -> Boolean = { true },
) : AppWidgetHostView(context) {

    private var codeView: View? = null
    private var codeLayoutId = 0

    override fun updateAppWidget(remoteViews: RemoteViews?) {
        val info = appWidgetInfo
        val pkg = info?.provider?.packageName
        val layoutId = remoteViews?.layoutId ?: info?.initialLayout ?: 0
        val remote = if (pkg != null && layoutId != 0 && allowsCode(pkg)) codeContext(context, pkg) else null
        if (remote == null || !needsCode(remote, pkg!!, layoutId)) {
            dropCodeView()
            super.updateAppWidget(remoteViews)
            return
        }
        try {
            val view = codeView?.takeIf { codeLayoutId == layoutId } ?: inflate(remote, layoutId)
            remoteViews?.let { runCatching { it.reapply(context, view) }.onFailure { e -> Log.w(TAG, "reapply $pkg", e) } }
        } catch (e: Throwable) {
            Log.w(TAG, "Couldn't inflate code widget $pkg", e)
            dropCodeView()
            super.updateAppWidget(remoteViews)
        }
    }

    private fun inflate(remote: Context, layoutId: Int): View {
        val view = LayoutInflater.from(remote).cloneInContext(remote).inflate(layoutId, this, false)
        dropCodeView()
        removeAllViews()
        addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        codeView = view
        codeLayoutId = layoutId
        // A picker preview (no id) is only drawn once, off screen.
        if (appWidgetId < 0) return view
        synchronized(CodeWidgetHost.live) { CodeWidgetHost.live.add(this) }
        // What vivo's launcher tells a newly shown widget.
        command(view, COMMAND_MOTION_INIT, Bundle().apply {
            putBoolean("hostVisible", CodeWidgetHost.visibleNow)
            putBoolean("hostLoading", false)
            putBoolean("hostDetectSupport", false)
            putBoolean("logEnable", false)
        })
        if (CodeWidgetHost.visibleNow) animWidgets(view).forEach { callAnim(it, "onActive", MOTION_INIT, DIRECTION_FROM_SELF) }
        return view
    }

    private fun dropCodeView() {
        val view = codeView ?: return
        if (appWidgetId >= 0) animWidgets(view).forEach { callAnim(it, "onRelease") }
        removeView(view)
        codeView = null
        codeLayoutId = 0
        synchronized(CodeWidgetHost.live) { CodeWidgetHost.live.remove(this) }
    }

    internal fun onHostVisible(visible: Boolean) {
        val view = codeView ?: return
        command(view, COMMAND_HOST_VISIBLE, Bundle().apply {
            putBoolean("hostVisible", visible)
            putBoolean("hostDetectSupport", false)
            putBoolean("logEnable", false)
        })
        animWidgets(view).forEach {
            if (visible) callAnim(it, "onActive", MOTION_WINDOW_RESUME, DIRECTION_FROM_SELF)
            else callAnim(it, "onInactive", MOTION_WINDOW_PAUSE)
        }
    }

    private fun command(view: View, command: Int, args: Bundle) {
        animWidgets(view).forEach { w ->
            runCatching {
                w.javaClass.getMethod("onCommandLauncherToWidget", Int::class.javaPrimitiveType, Bundle::class.java)
                    .invoke(w, command, args)
            }
        }
    }

    private fun callAnim(target: View, name: String, vararg args: Int) {
        runCatching {
            val types = Array<Class<*>>(args.size) { Int::class.javaPrimitiveType!! }
            target.javaClass.getMethod(name, *types).invoke(target, *args.toTypedArray())
        }.onFailure { Log.w(TAG, "$name failed", it) }
    }

    /** Views implementing vivo's com.vivo.common.widget.BBKAnimWidgetBase (absent off OriginOS). */
    private fun animWidgets(root: View): List<View> {
        val base = animBase ?: return emptyList()
        val out = mutableListOf<View>()
        fun walk(v: View) {
            if (base.isInstance(v)) out.add(v)
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(root)
        return out
    }

    companion object {
        private const val TAG = "CodeWidgetHostView"

        // com.vivo.common.widget.BBKAnimWidgetBase and BBKLauncher2's commands.
        private const val MOTION_INIT = 0
        private const val MOTION_WINDOW_RESUME = 4
        private const val MOTION_WINDOW_PAUSE = 8
        private const val DIRECTION_FROM_SELF = 2
        private const val COMMAND_MOTION_INIT = 700
        private const val COMMAND_HOST_VISIBLE = 720

        private val animBase: Class<*>? by lazy {
            runCatching { Class.forName("com.vivo.common.widget.BBKAnimWidgetBase") }.getOrNull()
        }

        /** By "package:layoutId": whether that layout uses the app's own view classes. */
        private val needsCodeCache = mutableMapOf<String, Boolean>()
        private val contexts = mutableMapOf<String, Context?>()

        /** The class loader of [pkg]'s code, if we have loaded it. */
        internal fun codeLoaderOf(pkg: String): ClassLoader? = synchronized(contexts) { contexts[pkg]?.classLoader }

        /** The widget app's context with its code loaded, or null if it isn't a preinstalled app. */
        fun codeContext(context: Context, pkg: String): Context? = synchronized(contexts) {
            contexts.getOrPut(pkg) {
                runCatching {
                    val app = context.packageManager.getApplicationInfo(pkg, 0)
                    if (app.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0) {
                        return@runCatching null
                    }
                    val remote = context.createPackageContext(
                        pkg, Context.CONTEXT_INCLUDE_CODE or Context.CONTEXT_IGNORE_SECURITY
                    )
                    if (app.theme != 0) ContextThemeWrapper(remote, app.theme) else remote
                }.getOrNull()
            }
        }

        /**
         * Whether [layoutId] names a View class that isn't one of Android's own
         * (those are written without a package, or under android.*).
         */
        fun needsCode(remote: Context, pkg: String, layoutId: Int): Boolean = synchronized(needsCodeCache) {
            needsCodeCache.getOrPut("$pkg:$layoutId") {
                val found = runCatching {
                    val parser = remote.resources.getLayout(layoutId)
                    try {
                        var custom = false
                        while (!custom) {
                            val event = parser.next()
                            if (event == XmlPullParser.END_DOCUMENT) break
                            if (event != XmlPullParser.START_TAG) continue
                            val name = parser.name
                            custom = '.' in name && !name.startsWith("android.")
                        }
                        custom
                    } finally {
                        parser.close()
                    }
                }.getOrDefault(false)
                if (found) CodeWidgetHost.codePackages.add(pkg)
                found
            }
        }
    }
}
