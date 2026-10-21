package com.arun.minimal_launcher

import android.content.Intent
import com.arun.minimal_launcher.platform.LauncherChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * The home-screen activity. Kept deliberately thin: all native features live in
 * [com.arun.minimal_launcher.platform] and are wired up here.
 */
class MainActivity : FlutterActivity() {

    private var launcherChannel: LauncherChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launcherChannel = LauncherChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        launcherChannel?.unregister()
        launcherChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Transparent Flutter surface so the system wallpaper shows through. */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

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
     * A normal app would finish(); a launcher must never close itself, so we
     * report the event as handled and do nothing.
     */
    override fun popSystemNavigator(): Boolean = true
}
