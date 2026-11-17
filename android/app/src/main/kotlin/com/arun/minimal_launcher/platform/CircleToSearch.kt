package com.arun.minimal_launcher.platform

import android.os.Bundle
import android.os.IBinder
import android.os.SystemClock
import org.lsposed.hiddenapibypass.HiddenApiBypass

/**
 * Opens Google's Circle to Search over whatever is on screen.
 *
 * Circle to Search is a session of the Google app as the phone's assistant,
 * started with an "omni" entry point (what the system does when the home
 * handle is held). The public way to start it needs a system-only
 * permission; this asks the assistant service for that same session
 * instead, the way other launchers on non-Pixel phones do. Tried in the
 * launcher's own process first, then from the Shizuku helper
 * ([com.arun.minimal_launcher.privileged.PrivilegedService]), which runs as
 * shell.
 */
object CircleToSearch {
    /** Null if the session was asked for, else why not. */
    fun start(): String? = try {
        HiddenApiBypass.addHiddenApiExemptions("")
        val binder = Class.forName("android.os.ServiceManager")
            .getMethod("getService", String::class.java)
            .invoke(null, "voiceinteraction") as IBinder?
            ?: throw IllegalStateException("No assistant service")
        val vims = Class.forName("com.android.internal.app.IVoiceInteractionManagerService\$Stub")
            .getMethod("asInterface", IBinder::class.java)
            .invoke(null, binder)!!
        val args = Bundle().apply {
            putLong("invocation_time_ms", SystemClock.elapsedRealtime())
            putInt("omni.entry_point", 1)
        }
        val show = vims.javaClass.methods.first { it.name == "showSessionFromSession" }
        // SHOW_WITH_ASSIST | SHOW_WITH_SCREENSHOT | SHOW_SOURCE_ASSIST_GESTURE
        val flags = 7
        val ok = when (show.parameterCount) {
            4 -> show.invoke(vims, null, args, flags, "hyperOS_home")
            3 -> show.invoke(vims, null, args, flags)
            else -> throw IllegalStateException("Unsupported Android version")
        } as? Boolean ?: true
        if (ok) null else "The assistant didn't open"
    } catch (e: Throwable) {
        val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
        cause.message ?: cause.javaClass.simpleName
    }
}
