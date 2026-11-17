package com.arun.minimal_launcher

import com.arun.minimal_launcher.platform.BrowserButtonService
import com.arun.minimal_launcher.platform.standby.StandbyMonitor
import io.flutter.app.FlutterApplication

/**
 * Starts what must run without the home screen open: the standby clock's
 * lock-screen watcher, and the browsers' full-screen button (back on after an update). As the home app this process is kept alive, and is
 * started again after a reboot.
 */
class LauncherApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        StandbyMonitor.init(this)
        BrowserButtonService.restoreIfWanted(this)
    }
}
