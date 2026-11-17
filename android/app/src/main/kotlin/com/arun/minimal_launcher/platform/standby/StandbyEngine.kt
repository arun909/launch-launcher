package com.arun.minimal_launcher.platform.standby

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The standby clock's own Flutter engine (the `standbyMain` entrypoint in
 * lib/main.dart), made once and kept, paused, between showings so the clock
 * opens instantly. It draws nothing and wakes nothing while hidden.
 */
object StandbyEngine {

    private const val ENTRYPOINT = "standbyMain"

    private var engine: FlutterEngine? = null
    var channel: StandbyChannel? = null
        private set

    fun warm(context: Context) {
        get(context)
    }

    fun get(context: Context): FlutterEngine = engine ?: FlutterEngine(context.applicationContext).also { e ->
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(FlutterInjector.instance().flutterLoader().findAppBundlePath(), ENTRYPOINT)
        )
        channel = StandbyChannel(context.applicationContext, e.dartExecutor.binaryMessenger).also { it.register() }
        engine = e
    }
}
