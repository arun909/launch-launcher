package com.arun.minimal_launcher

import android.content.Intent
import android.content.res.Configuration
import com.arun.minimal_launcher.platform.AppWidgetsChannel
import com.arun.minimal_launcher.platform.ControlsChannel
import com.arun.minimal_launcher.platform.SoundChannel
import com.arun.minimal_launcher.platform.DeviceStatsChannel
import com.arun.minimal_launcher.platform.DisplayRefreshRate
import com.arun.minimal_launcher.platform.InstantChannel
import com.arun.minimal_launcher.platform.LauncherChannel
import com.arun.minimal_launcher.platform.RotationChannel
import com.arun.minimal_launcher.platform.SystemAppsChannel
import com.arun.minimal_launcher.platform.WindowBlurChannel
import com.arun.minimal_launcher.platform.standby.StandbyChannel
import com.arun.minimal_launcher.platform.standby.StandbyMonitor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * The home-screen activity. Kept deliberately thin: all native features live in
 * [com.arun.minimal_launcher.platform] and are wired up here.
 */
class MainActivity : FlutterActivity() {

    private var launcherChannel: LauncherChannel? = null
    private var systemAppsChannel: SystemAppsChannel? = null
    private var windowBlurChannel: WindowBlurChannel? = null
    private var appWidgetsChannel: AppWidgetsChannel? = null
    private var rotationChannel: RotationChannel? = null
    private var standbyChannel: StandbyChannel? = null
    private var instantChannel: InstantChannel? = null
    private var deviceStatsChannel: DeviceStatsChannel? = null
    private var controlsChannel: ControlsChannel? = null
    private var soundChannel: SoundChannel? = null

    /** App widgets on the home screen update only while we're visible. */
    override fun onStart() {
        super.onStart()
        appWidgetsChannel?.startListening()
    }

    override fun onStop() {
        appWidgetsChannel?.stopListening()
        rotationChannel?.reset()
        super.onStop()
    }

    /** The widget bind-permission and widget setup screens report back here. */
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (appWidgetsChannel?.onActivityResult(requestCode, resultCode) == true) return
        if (instantChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Night mode changes arrive here (uiMode is in configChanges). */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        controlsChannel?.onConfigurationChanged(newConfig)
    }

    /** Ask for 120 Hz each time we come to the front (OEMs may reset it). */
    override fun onResume() {
        super.onResume()
        DisplayRefreshRate.requestHighest(this)
        rotationChannel?.start()
        StandbyMonitor.ensureRunning(this)
        StandbyMonitor.homeInFront = true
    }

    override fun onPause() {
        StandbyMonitor.homeInFront = false
        rotationChannel?.stop()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launcherChannel = LauncherChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        systemAppsChannel = SystemAppsChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // Needs the activity (its window), not the application context.
        windowBlurChannel = WindowBlurChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // Needs the activity: adding a widget may open Android's permission
        // and setup screens for a result.
        appWidgetsChannel = AppWidgetsChannel(
            this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.platformViewsController.registry
        ).also { it.register() }
        // Needs the activity: it locks this activity's orientation.
        rotationChannel = RotationChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // Standby settings: on/off and "Show now".
        // The activity too: turning on the beat pulse asks for a permission.
        standbyChannel = StandbyChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger, this)
            .also { it.register() }
        // The instant-search widget. The activity: the scanner, voice input
        // and photo picker report back to it.
        instantChannel = InstantChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // Phone-stats widget and the clock's weather. The activity: it asks
        // for Bluetooth and location and opens Usage access.
        deviceStatsChannel = DeviceStatsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // The control center's brightness and display controls.
        controlsChannel = ControlsChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        // The control center's volume, ringer mode and Do Not Disturb.
        soundChannel = SoundChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        launcherChannel?.unregister()
        launcherChannel = null
        systemAppsChannel?.unregister()
        systemAppsChannel = null
        windowBlurChannel?.unregister()
        windowBlurChannel = null
        appWidgetsChannel?.stopListening()
        appWidgetsChannel?.unregister()
        appWidgetsChannel = null
        rotationChannel?.unregister()
        rotationChannel = null
        standbyChannel?.unregister()
        standbyChannel = null
        instantChannel?.unregister()
        instantChannel = null
        deviceStatsChannel?.unregister()
        deviceStatsChannel = null
        controlsChannel?.unregister()
        controlsChannel = null
        soundChannel?.unregister()
        soundChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Transparent Flutter surface so the system wallpaper shows through. */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    /**
     * Flutter picks the slower TextureView for transparent backgrounds by
     * default (an extra copy every frame). SurfaceView supports transparency
     * too, and is composited directly by the system, so use it.
     */
    override fun getRenderMode(): RenderMode = RenderMode.surface

    /**
     * Because the activity is singleTask, pressing Home while the launcher is
     * already in front arrives here. Forward it so Dart can return to the home
     * screen (close the drawer / settings).
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_HOME)) {
            launcherChannel?.notifyHomePressed()
        }
    }

    /**
     * Called when Flutter has nothing left to pop (e.g. SystemNavigator.pop()).
     * As the default home screen we must never close ourselves, so we report
     * it as handled. Opened as a normal app, Back exits as usual.
     */
    override fun popSystemNavigator(): Boolean =
        LauncherChannel.isDefaultHome(this) || super.popSystemNavigator()
}
