package com.arun.minimal_launcher.platform

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.lsposed.hiddenapibypass.HiddenApiBypass
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The phone-stats widget's native side (today's screen time and unlocks,
 * the battery, connected Bluetooth devices' batteries) and the clock's
 * weather location.
 * Mirrors lib/core/platform/device_stats_platform.dart — keep both in sync.
 *
 * Method channel `com.arun.minimal_launcher/device_stats`
 *   stats() -> Map:
 *     battery: Int (0–100), charging: Boolean,
 *     usageAccess: Boolean, screenOnMs: Long? and unlocks: Int? (today, since midnight; null without usage access),
 *     uptimeMs: Long (since the phone last started),
 *     topApps: List<Map{package: String, ms: Long}>? (today's most used apps, most first, at most 5;
 *       null without usage access),
 *     bluetoothAllowed: Boolean,
 *     bluetooth: List<Map{name: String, address: String, battery: Int (-1 unknown), kind: String}>
 *       (kind: headphones | watch | input | phone | computer | car | other)
 *   openUsageAccess()        Android's Usage access page, at this app.
 *   requestBluetooth()       Android's "Nearby devices" dialog; once refused for good, this app's settings.
 *   hasLocation() -> Boolean (approximate location allowed)
 *   requestLocation()        As requestBluetooth, for approximate location.
 *   location() -> Map{lat: Double, lon: Double, place: String?}? (null: no permission or no fix)
 *
 * Event channel `com.arun.minimal_launcher/device_stats_events`: an event
 * (null) whenever something shown may have changed — battery, a device
 * connecting or its battery, an unlock. Dart reads stats() again then.
 */
class DeviceStatsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val context: Context = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val events = EventChannel(messenger, EVENTS)
    private val main = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val prefs = context.getSharedPreferences("device_stats", Context.MODE_PRIVATE)

    private var sink: EventChannel.EventSink? = null

    /** Profile proxies (headphones, hands-free…): their connected devices are public API. */
    private val proxies = ConcurrentHashMap<Int, BluetoothProfile>()

    fun register() {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun unregister() {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        onCancel(null)
        closeProxies()
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "stats" -> {
                openProxies()
                inBackground(result) { stats() }
            }
            "openUsageAccess" -> {
                openUsageAccess()
                result.success(null)
            }
            "requestBluetooth" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    request(Manifest.permission.BLUETOOTH_CONNECT, KEY_BT_ASKED, REQUEST_BLUETOOTH)
                }
                result.success(null)
            }
            "hasLocation" -> result.success(hasLocation())
            "requestLocation" -> {
                request(Manifest.permission.ACCESS_COARSE_LOCATION, KEY_LOCATION_ASKED, REQUEST_LOCATION)
                result.success(null)
            }
            "location" -> location(result)
            else -> result.notImplemented()
        }
    }

    // ---- Changes ---------------------------------------------------------

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            if (intent.action == ACTION_BT_BATTERY) {
                val device = deviceOf(intent)
                val level = intent.getIntExtra(EXTRA_BT_BATTERY, -1)
                if (device != null && level >= 0) btBattery[device.address] = level
            }
            if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                // Sent often (temperature, voltage); only a new level or plug matters.
                val key = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 10 +
                    intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                if (key == lastBatteryKey) return
                lastBatteryKey = key
            }
            sink?.success(null)
        }
    }
    private var lastBatteryKey = Int.MIN_VALUE

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        openProxies()
        val system = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        val bluetooth = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(ACTION_BT_BATTERY)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, system, Context.RECEIVER_NOT_EXPORTED)
            // Sent by the Bluetooth app, not the system: needs EXPORTED.
            context.registerReceiver(receiver, bluetooth, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, system)
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, bluetooth)
        }
    }

    override fun onCancel(arguments: Any?) {
        if (sink == null) return
        sink = null
        runCatching { context.unregisterReceiver(receiver) }
    }

    // ---- Stats -----------------------------------------------------------

    private fun stats(): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.let {
            val l = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val s = it.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (l >= 0 && s > 0) l * 100 / s else null
        } ?: (context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
            .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        val access = hasUsageAccess()
        val today = if (access) runCatching { screenToday() }.getOrNull() else null
        val btAllowed = bluetoothAllowed()
        return mapOf(
            "battery" to level.coerceIn(0, 100),
            "charging" to charging,
            "usageAccess" to access,
            "screenOnMs" to today?.first,
            "unlocks" to today?.second,
            "uptimeMs" to SystemClock.elapsedRealtime(),
            "topApps" to today?.third,
            "bluetoothAllowed" to btAllowed,
            "bluetooth" to if (btAllowed) runCatching { bluetoothDevices() }.getOrDefault(emptyList()) else emptyList(),
        )
    }

    private fun hasUsageAccess(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return if (mode == AppOpsManager.MODE_DEFAULT) {
            context.checkSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) == PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    }

    /**
     * (screen-on time in ms, unlocks, most used apps) since midnight, from
     * Android's own usage events (as Digital Wellbeing counts them): the
     * screen turning on and off, the lock screen going away, and apps'
     * activities coming to the front and leaving it.
     */
    private fun screenToday(): Triple<Long, Int, List<Map<String, Any>>> {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val now = System.currentTimeMillis()
        val list = usm.queryEvents(start, now)
        val e = UsageEvents.Event()
        var onSince: Long? = null
        var seenAny = false
        var total = 0L
        var unlocks = 0

        // The app in front and since when; time per package.
        val perApp = HashMap<String, Long>()
        var front: String? = null
        var frontSince = 0L
        var seenActivity = false
        fun close(at: Long) {
            val p = front ?: return
            perApp[p] = (perApp[p] ?: 0L) + (at - frontSince).coerceAtLeast(0)
            front = null
        }

        while (list.hasNextEvent()) {
            list.getNextEvent(e)
            when (e.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    if (onSince == null) onSince = e.timeStamp
                    seenAny = true
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    // The first event of the day an "off": it was on since midnight.
                    val from = onSince ?: if (!seenAny) start else e.timeStamp
                    total += e.timeStamp - from
                    onSince = null
                    seenAny = true
                    close(e.timeStamp)
                }
                UsageEvents.Event.KEYGUARD_HIDDEN -> unlocks++
                ACTIVITY_RESUMED -> {
                    if (front != e.packageName) {
                        close(e.timeStamp)
                        front = e.packageName
                        frontSince = e.timeStamp
                    }
                    seenActivity = true
                }
                ACTIVITY_PAUSED, ACTIVITY_STOPPED -> {
                    // Open since before midnight: count from midnight.
                    if (front == null && !seenActivity) {
                        front = e.packageName
                        frontSince = start
                    }
                    if (front == e.packageName) close(e.timeStamp)
                    seenActivity = true
                }
            }
        }
        val interactive = (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        when {
            onSince != null -> total += now - onSince
            !seenAny && interactive -> total += now - start
        }
        if (interactive) close(now)

        val skip = homeAndSystemUi()
        val top = perApp.entries
            .filter { it.key !in skip && it.value >= 60_000 }
            .sortedByDescending { it.value }
            .take(5)
            .map { mapOf("package" to it.key, "ms" to it.value) }
        return Triple(total.coerceAtLeast(0), unlocks, top)
    }

    /** Not "apps used": this launcher, other launchers, and the system's own screens. */
    private fun homeAndSystemUi(): Set<String> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val launchers = runCatching {
            context.packageManager.queryIntentActivities(home, 0).map { it.activityInfo.packageName }
        }.getOrDefault(emptyList())
        return launchers.toSet() + context.packageName + "com.android.systemui" + "android"
    }

    // ---- Bluetooth -------------------------------------------------------

    private fun bluetoothAllowed(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** Headphones, hands-free, hearing aids, LE audio: whose connected devices we can list publicly. */
    private fun openProxies() {
        val a = adapter ?: return
        if (!bluetoothAllowed() || proxies.size >= PROFILES.size) return
        for (profile in PROFILES) {
            if (proxies.containsKey(profile)) continue
            runCatching {
                a.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(p: Int, proxy: BluetoothProfile) {
                        proxies[p] = proxy
                        sink?.let { s -> main.post { s.success(null) } }
                    }
                    override fun onServiceDisconnected(p: Int) {
                        proxies.remove(p)
                    }
                }, profile)
            }
        }
    }

    private fun closeProxies() {
        val a = adapter
        for ((p, proxy) in proxies) runCatching { a?.closeProfileProxy(p, proxy) }
        proxies.clear()
    }

    @Suppress("MissingPermission")
    private fun bluetoothDevices(): List<Map<String, Any?>> {
        val a = adapter ?: return emptyList()
        if (!a.isEnabled) return emptyList()
        val connected = LinkedHashMap<String, BluetoothDevice>()
        for (proxy in proxies.values) {
            runCatching { proxy.connectedDevices }.getOrNull()?.forEach { connected[it.address] = it }
        }
        // Watches, keyboards… aren't in an audio profile: every paired device that's linked.
        runCatching { a.bondedDevices }.getOrNull()?.forEach { d ->
            if (!connected.containsKey(d.address) && hidden(d, "isConnected") == true) connected[d.address] = d
        }
        return connected.values.map { d ->
            val level = (hidden(d, "getBatteryLevel") as? Int)?.takeIf { it in 0..100 }
                ?: btBattery[d.address] ?: -1
            mapOf(
                "name" to ((if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) runCatching { d.alias }.getOrNull() else null)
                    ?: runCatching { d.name }.getOrNull() ?: "Device"),
                "address" to d.address,
                "battery" to level,
                "kind" to kindOf(d),
            )
        }
    }

    /**
     * Calls one of BluetoothDevice's hidden getters (battery level, linked).
     * They're system APIs, but only check BLUETOOTH_CONNECT; plain
     * reflection first, then past Android's hidden-API list.
     */
    private fun hidden(d: BluetoothDevice, name: String): Any? =
        runCatching { BluetoothDevice::class.java.getMethod(name).invoke(d) }.getOrNull()
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                runCatching { HiddenApiBypass.invoke(BluetoothDevice::class.java, d, name) }.getOrNull()
            } else {
                null
            }

    @Suppress("MissingPermission")
    private fun kindOf(d: BluetoothDevice): String {
        val c = runCatching { d.bluetoothClass }.getOrNull() ?: return "other"
        return when (c.majorDeviceClass) {
            BluetoothClass.Device.Major.AUDIO_VIDEO -> when (c.deviceClass) {
                BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO -> "car"
                BluetoothClass.Device.AUDIO_VIDEO_LOUDSPEAKER,
                BluetoothClass.Device.AUDIO_VIDEO_PORTABLE_AUDIO,
                BluetoothClass.Device.AUDIO_VIDEO_HIFI_AUDIO -> "speaker"
                else -> "headphones"
            }
            BluetoothClass.Device.Major.WEARABLE -> "watch"
            BluetoothClass.Device.Major.PERIPHERAL -> "input"
            BluetoothClass.Device.Major.PHONE -> "phone"
            BluetoothClass.Device.Major.COMPUTER -> "computer"
            else -> "other"
        }
    }

    private fun deviceOf(intent: Intent): BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
    } else {
        @Suppress("DEPRECATION")
        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
    }

    // ---- Location (the clock's weather) ----------------------------------

    private fun hasLocation(): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** The newest fix any provider has; a fresh one if none is under an hour old. */
    @Suppress("MissingPermission")
    private fun location(result: MethodChannel.Result) {
        if (!hasLocation()) return result.success(null)
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val last = listOf(LocationManager.NETWORK_PROVIDER, "fused", LocationManager.PASSIVE_PROVIDER, LocationManager.GPS_PROVIDER)
            .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
        val fresh = last != null && System.currentTimeMillis() - last.time < 60 * 60 * 1000
        if (fresh || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return reply(result, last)
        val provider = listOf(LocationManager.NETWORK_PROVIDER, "fused", LocationManager.GPS_PROVIDER)
            .firstOrNull { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
            ?: return reply(result, last)
        var done = false
        val timeout = Runnable { if (!done) { done = true; reply(result, last) } }
        main.postDelayed(timeout, 15_000)
        runCatching {
            lm.getCurrentLocation(provider, null, worker) { loc ->
                main.post {
                    if (done) return@post
                    done = true
                    main.removeCallbacks(timeout)
                    reply(result, loc ?: last)
                }
            }
        }.onFailure { main.removeCallbacks(timeout); if (!done) { done = true; reply(result, last) } }
    }

    /** [loc] with its town's name (best effort, off the main thread). */
    private fun reply(result: MethodChannel.Result, loc: Location?) {
        if (loc == null) return result.success(null)
        inBackground(result) {
            val place = runCatching {
                @Suppress("DEPRECATION")
                Geocoder(context, Locale.getDefault()).getFromLocation(loc.latitude, loc.longitude, 1)
                    ?.firstOrNull()?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
            }.getOrNull()
            mapOf("lat" to loc.latitude, "lon" to loc.longitude, "place" to place)
        }
    }

    // ---- Permissions -----------------------------------------------------

    private fun openUsageAccess() {
        val withPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .setData(Uri.fromParts("package", context.packageName, null))
        runCatching { activity.startActivity(withPackage) }
            .onFailure { runCatching { activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) } }
    }

    /**
     * Android's dialog; once it was refused for good (it no longer shows),
     * this app's settings page, where it can still be allowed.
     */
    private fun request(permission: String, askedKey: String, code: Int) {
        if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return
        val askedBefore = prefs.getBoolean(askedKey, false)
        if (askedBefore && !activity.shouldShowRequestPermissionRationale(permission)) {
            activity.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", context.packageName, null)),
            )
            return
        }
        prefs.edit().putBoolean(askedKey, true).apply()
        activity.requestPermissions(arrayOf(permission), code)
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            val r = runCatching(work)
            main.post {
                r.onSuccess { result.success(it) }
                    .onFailure { result.error("FAILED", it.message, null) }
            }
        }
    }

    companion object {
        // UsageEvents.Event.ACTIVITY_RESUMED / _PAUSED / _STOPPED (API 29 names, same values before).
        private const val ACTIVITY_RESUMED = 1
        private const val ACTIVITY_PAUSED = 2
        private const val ACTIVITY_STOPPED = 23
        const val CHANNEL = "com.arun.minimal_launcher/device_stats"
        const val EVENTS = "com.arun.minimal_launcher/device_stats_events"

        /** Hidden: sent by the Bluetooth app when a hands-free device reports its battery. */
        private const val ACTION_BT_BATTERY = "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED"
        private const val EXTRA_BT_BATTERY = "android.bluetooth.device.extra.BATTERY_LEVEL"

        private const val KEY_BT_ASKED = "bluetoothAsked"
        private const val KEY_LOCATION_ASKED = "locationAsked"
        private const val REQUEST_BLUETOOTH = 7301
        private const val REQUEST_LOCATION = 7302

        /** A2DP, HEADSET, HEARING_AID (21), LE_AUDIO (22). */
        private val PROFILES = listOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET, 21, 22)

        /** Last battery each device reported (by address), for this process. */
        private val btBattery = ConcurrentHashMap<String, Int>()
    }
}
