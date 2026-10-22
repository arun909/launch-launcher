package com.arun.minimal_launcher.privileged

import android.content.ComponentName
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import rikka.shizuku.Shizuku
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * App-side handle to [PrivilegedService], started on demand through Shizuku.
 *
 * Callers must already hold Shizuku permission (see SystemAppsChannel).
 */
class PrivilegedServiceClient(packageName: String, version: Int) {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var service: IPrivilegedService? = null
    @Volatile private var connected = CountDownLatch(1)

    private val args = Shizuku.UserServiceArgs(ComponentName(packageName, PrivilegedService::class.java.name))
        .daemon(false) // dies with the app; nothing keeps running in the background
        .processNameSuffix("privileged")
        .version(version) // bump (via versionCode) so Shizuku reloads changed service code

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (binder != null && binder.pingBinder()) {
                service = IPrivilegedService.Stub.asInterface(binder)
            }
            connected.countDown()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    /** Blocking: binds if needed. Call from a background thread. */
    fun get(timeoutMs: Long = 10_000): IPrivilegedService {
        service?.takeIf { it.asBinder().pingBinder() }?.let { return it }
        connected = CountDownLatch(1)
        mainHandler.post { Shizuku.bindUserService(args, connection) }
        if (!connected.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            throw IllegalStateException("Shizuku didn't start the helper service in time")
        }
        return service ?: throw IllegalStateException("Shizuku helper service is unavailable")
    }

    fun release() {
        if (service == null) return
        try {
            Shizuku.unbindUserService(args, connection, true)
        } catch (_: Exception) {
            // Shizuku already gone; nothing to release.
        }
        service = null
    }
}
