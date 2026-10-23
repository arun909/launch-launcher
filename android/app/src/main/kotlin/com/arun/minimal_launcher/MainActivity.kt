package com.arun.minimal_launcher

import android.content.Intent
import android.os.Bundle
import com.arun.minimal_launcher.platform.DisplayRefreshRate
import com.arun.minimal_launcher.platform.LauncherChannel
import com.arun.minimal_launcher.platform.SystemAppsChannel
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DisplayRefreshRate.requestHighest(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launcherChannel = LauncherChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        systemAppsChannel = SystemAppsChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        launcherChannel?.unregister()
        launcherChannel = null
        systemAppsChannel?.unregister()
        systemAppsChannel = null
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
