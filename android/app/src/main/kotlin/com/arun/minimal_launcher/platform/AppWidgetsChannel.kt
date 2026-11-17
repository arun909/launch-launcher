package com.arun.minimal_launcher.platform

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Hosts other apps' home-screen widgets (Android app widgets).
 * Mirrors lib/core/platform/app_widgets_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/app_widgets`
 *   Dart -> Android:
 *   getProviders()                     -> List<Map>  every widget installed apps offer
 *   getPreview({provider, widthDp, heightDp, sizePx})
 *                                      -> ByteArray? PNG: its preview layout drawn at that
 *                                                    size (Android 12+), else its preview
 *                                                    image, else its icon
 *   addWidget({provider, widthDp, heightDp})
 *                                      -> Int?       a bound, configured appWidgetId, told its
 *                                                    size up front; null if the user cancelled
 *   reconfigure({appWidgetId})         -> Boolean    reopens its settings screen
 *   deleteWidget({appWidgetId})        -> null       releases the id
 *   keepOnly({appWidgetIds})           -> null       releases every other id of ours
 *   setLook({appWidgetId, radius, scale})
 *                                      -> null       a shown widget's corner radius (dp) and
 *                                                    how much it's scaled down to fit
 *   Android -> Dart:
 *   onScrollable({appWidgetId, scrollable})          whether a shown widget holds a list or
 *                                                    grid, so Dart can pass it vertical drags
 *
 * Widgets are drawn by the `com.arun.minimal_launcher/app_widget` platform view
 * (see AppWidgetPlatformView).
 *
 * Only this launcher's own widget host is touched: binding a widget lets just
 * this app show it, and Android drops all of it when the launcher is
 * uninstalled. The phone itself is left as it was.
 */
class AppWidgetsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val views: PlatformViewRegistry,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val manager = AppWidgetManager.getInstance(activity)
    val host = CodeWidgetHost(activity.applicationContext, HOST_ID)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()

    /** A widget being added: waiting for the bind permission or its setup screen. */
    private class Pending(val appWidgetId: Int, val info: AppWidgetProviderInfo, val result: MethodChannel.Result)

    private var pending: Pending? = null

    private val viewFactory = AppWidgetViewFactory(host, manager) { id, scrollable ->
        methodChannel.invokeMethod("onScrollable", mapOf("appWidgetId" to id, "scrollable" to scrollable))
    }

    fun register() {
        methodChannel.setMethodCallHandler(this)
        views.registerViewFactory(VIEW_TYPE, viewFactory)
    }

    fun unregister() {
        methodChannel.setMethodCallHandler(null)
        worker.shutdownNow()
    }

    /** Widgets only update while their host listens; MainActivity calls these from onStart / onStop. */
    fun startListening() = runCatching {
        host.startListening()
        host.setVisible(true)
    }

    fun stopListening() = runCatching {
        host.setVisible(false)
        host.stopListening()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getProviders" -> inBackground(result) { manager.installedProviders.map(::describe) }

            "getPreview" -> {
                val info = call.argument<String>("provider")?.let(::findProvider)
                val size = call.argument<Int>("sizePx") ?: DEFAULT_PREVIEW_PX
                val widthDp = call.argument<Double>("widthDp") ?: 0.0
                val heightDp = call.argument<Double>("heightDp") ?: 0.0
                if (info == null) {
                    result.success(null)
                    return
                }
                // Views are drawn on the main thread; only the PNG encoding is moved off it.
                val drawn = runCatching { layoutPreview(info, widthDp, heightDp, size) }.getOrNull()
                inBackground(result) { drawn?.let { it.toPng() } ?: preview(info, size) }
            }

            "addWidget" -> {
                val info = call.argument<String>("provider")?.let(::findProvider)
                val size = sizeOptions(call.argument<Double>("widthDp"), call.argument<Double>("heightDp"))
                when {
                    info == null -> result.success(null)
                    pending != null -> result.error("BUSY", "A widget is already being added", null)
                    else -> add(info, size, result)
                }
            }

            "reconfigure" -> {
                val id = call.argument<Int>("appWidgetId")
                result.success(
                    id != null && runCatching {
                        host.startAppWidgetConfigureActivityForResult(activity, id, 0, REQUEST_RECONFIGURE, null)
                    }.isSuccess
                )
            }

            "setLook" -> {
                val id = call.argument<Int>("appWidgetId")
                val radius = call.argument<Double>("radius")
                val scale = call.argument<Double>("scale")
                if (id != null && radius != null && scale != null) {
                    viewFactory.setLook(id, radius.toFloat(), scale.toFloat())
                }
                result.success(null)
            }

            "deleteWidget" -> {
                call.argument<Int>("appWidgetId")?.let { host.deleteAppWidgetId(it) }
                result.success(null)
            }

            "keepOnly" -> {
                val keep = call.argument<List<Int>>("appWidgetIds")?.toSet() ?: emptySet()
                // Ids left behind by widgets removed while the app was killed, or
                // an add that never finished.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && pending == null) {
                    host.appWidgetIds.filterNot(keep::contains).forEach(host::deleteAppWidgetId)
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * The size a widget will be shown at, as AppWidgetManager options, so it
     * lays itself out for it from the very first update (null if not known).
     */
    private fun sizeOptions(widthDp: Double?, heightDp: Double?): Bundle? {
        if (widthDp == null || heightDp == null || widthDp <= 0 || heightDp <= 0) return null
        val w = widthDp.roundToInt()
        val h = heightDp.roundToInt()
        return Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, w)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, w)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, h)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, h)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                putParcelableArrayList(
                    AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf(SizeF(widthDp.toFloat(), heightDp.toFloat()))
                )
            }
        }
    }

    private fun add(info: AppWidgetProviderInfo, size: Bundle?, result: MethodChannel.Result) {
        val id = host.allocateAppWidgetId()
        pending = Pending(id, info, result)
        if (manager.bindAppWidgetIdIfAllowed(id, info.profile, info.provider, size)) {
            configure()
            return
        }
        // Not yet allowed: Android asks the user once ("Allow … to create widgets").
        val ask = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, info.provider)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER_PROFILE, info.profile)
            .apply { if (size != null) putExtra(AppWidgetManager.EXTRA_APPWIDGET_OPTIONS, size) }
        try {
            activity.startActivityForResult(ask, REQUEST_BIND)
        } catch (_: ActivityNotFoundException) {
            finish(false)
        }
    }

    /** Opens the widget's own setup screen, if it has one. */
    private fun configure() {
        val p = pending ?: return
        if (p.info.configure == null || configurationOptional(p.info)) {
            finish(true)
            return
        }
        try {
            host.startAppWidgetConfigureActivityForResult(activity, p.appWidgetId, 0, REQUEST_CONFIGURE, null)
        } catch (_: Exception) {
            finish(false)
        }
    }

    private fun configurationOptional(info: AppWidgetProviderInfo): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_CONFIGURATION_OPTIONAL != 0 &&
            info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_RECONFIGURABLE != 0

    private fun finish(added: Boolean) {
        val p = pending ?: return
        pending = null
        if (added) {
            p.result.success(p.appWidgetId)
        } else {
            host.deleteAppWidgetId(p.appWidgetId)
            p.result.success(null)
        }
    }

    /** From MainActivity. True if the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        val ok = resultCode == Activity.RESULT_OK
        when (requestCode) {
            REQUEST_BIND -> if (ok) configure() else finish(false)
            REQUEST_CONFIGURE -> finish(ok)
            REQUEST_RECONFIGURE -> Unit // The widget updates itself.
            else -> return false
        }
        return true
    }

    private fun findProvider(flattened: String): AppWidgetProviderInfo? {
        val component = ComponentName.unflattenFromString(flattened) ?: return null
        return manager.installedProviders.firstOrNull { it.provider == component }
    }

    private fun describe(info: AppWidgetProviderInfo): Map<String, Any?> {
        val pm = activity.packageManager
        val density = activity.resources.displayMetrics.density
        val appLabel = runCatching {
            pm.getApplicationLabel(pm.getApplicationInfo(info.provider.packageName, 0)).toString()
        }.getOrDefault(info.provider.packageName)
        val s = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        return mapOf(
            "provider" to info.provider.flattenToString(),
            "packageName" to info.provider.packageName,
            "label" to info.loadLabel(pm),
            "appLabel" to appLabel,
            "description" to if (s) info.loadDescription(activity)?.toString() else null,
            "minWidthDp" to (info.minWidth / density).roundToInt(),
            "minHeightDp" to (info.minHeight / density).roundToInt(),
            // 0 = not set (then the min size above is also the least).
            "minResizeWidthDp" to (info.minResizeWidth / density).roundToInt(),
            "minResizeHeightDp" to (info.minResizeHeight / density).roundToInt(),
            "maxResizeWidthDp" to if (s) (info.maxResizeWidth / density).roundToInt() else 0,
            "maxResizeHeightDp" to if (s) (info.maxResizeHeight / density).roundToInt() else 0,
            "resizeHorizontal" to (info.resizeMode and AppWidgetProviderInfo.RESIZE_HORIZONTAL != 0),
            "resizeVertical" to (info.resizeMode and AppWidgetProviderInfo.RESIZE_VERTICAL != 0),
            // Launcher3's rule for offering "Widget settings" later.
            "reconfigurable" to (
                info.configure != null && s &&
                    info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_RECONFIGURABLE != 0
                ),
            "targetCellWidth" to if (s) info.targetCellWidth else 0,
            "targetCellHeight" to if (s) info.targetCellHeight else 0,
        )
    }

    private fun preview(info: AppWidgetProviderInfo, sizePx: Int): ByteArray? {
        val density = activity.resources.displayMetrics.densityDpi
        val drawable = info.loadPreviewImage(activity, density) ?: info.loadIcon(activity, density) ?: return null
        return drawable.toPng(sizePx)
    }

    /**
     * Android 12+ widgets often have no preview image, only a preview layout:
     * inflate it in a host view off screen, at the size it will have on the
     * home screen, and draw that. Null if it has none (or fails to inflate).
     */
    private fun layoutPreview(info: AppWidgetProviderInfo, widthDp: Double, heightDp: Double, maxPx: Int): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || info.previewLayout == 0) return null
        val density = activity.resources.displayMetrics.density
        val w = max(((if (widthDp > 0) widthDp.toFloat() else info.minWidth / density) * density).roundToInt(), 1)
        val h = max(((if (heightDp > 0) heightDp.toFloat() else info.minHeight / density) * density).roundToInt(), 1)
        // CodeWidgetHostView: OriginOS previews are built from their app's own views too.
        val view = CodeWidgetHostView(activity).apply {
            setPadding(0, 0, 0, 0)
            setAppWidget(-1, info)
            updateAppWidget(RemoteViews(info.provider.packageName, info.previewLayout))
            measure(
                View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY),
            )
            layout(0, 0, w, h)
        }
        val scale = minOf(1f, maxPx.toFloat() / max(w, h))
        val bitmap = Bitmap.createBitmap(max((w * scale).roundToInt(), 1), max((h * scale).roundToInt(), 1), Bitmap.Config.ARGB_8888)
        Canvas(bitmap).apply {
            scale(scale, scale)
            view.draw(this)
        }
        return bitmap
    }

    private fun Bitmap.toPng(): ByteArray = ByteArrayOutputStream().use {
        compress(Bitmap.CompressFormat.PNG, 100, it)
        recycle()
        it.toByteArray()
    }

    private fun Drawable.toPng(maxPx: Int): ByteArray {
        val w = max(intrinsicWidth, 1)
        val h = max(intrinsicHeight, 1)
        val scale = minOf(1f, maxPx.toFloat() / max(w, h))
        val bitmap = Bitmap.createBitmap(
            max((w * scale).roundToInt(), 1), max((h * scale).roundToInt(), 1), Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        setBounds(0, 0, canvas.width, canvas.height)
        draw(canvas)
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            bitmap.recycle()
            it.toByteArray()
        }
    }

    /** Runs [work] on the worker thread and replies on the main thread (required by Flutter). */
    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
    }

    companion object {
        const val METHOD_CHANNEL = "com.arun.minimal_launcher/app_widgets"
        const val VIEW_TYPE = "com.arun.minimal_launcher/app_widget"
        private const val HOST_ID = 0x4d4c
        private const val REQUEST_BIND = 0x4d01
        private const val REQUEST_CONFIGURE = 0x4d02
        private const val REQUEST_RECONFIGURE = 0x4d03
        private const val DEFAULT_PREVIEW_PX = 480
    }
}
