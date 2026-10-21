package com.arun.minimal_launcher.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Streams package install / uninstall / update events to Dart so the app list
 * refreshes without a restart.
 *
 * Each event is a map: { "type": "added" | "removed" | "changed", "packageName": String }.
 * The receiver is registered only while Dart is listening.
 */
class PackageEventsStreamHandler(private val context: Context) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val pkg = intent.data?.schemeSpecificPart ?: return
                // An update fires REMOVED(replacing) + ADDED(replacing) + REPLACED;
                // only REPLACED is interesting in that case.
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                val type = when (intent.action) {
                    Intent.ACTION_PACKAGE_ADDED -> if (replacing) null else "added"
                    Intent.ACTION_PACKAGE_REMOVED -> if (replacing) null else "removed"
                    Intent.ACTION_PACKAGE_CHANGED, Intent.ACTION_PACKAGE_REPLACED -> "changed"
                    else -> null
                } ?: return
                events.success(mapOf("type" to type, "packageName" to pkg))
            }
        }
        // NOT_EXPORTED still receives protected system broadcasts like these;
        // it only blocks other apps from sending to this receiver.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(r, filter)
        }
        receiver = r
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
    }
}
