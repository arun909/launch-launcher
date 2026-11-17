package com.arun.minimal_launcher.platform.standby

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Which players have played since the phone was locked, so the standby
 * tile keeps a song paused on the lock screen (or in standby) until the next
 * unlock, but never brings up one that was already paused when the phone
 * was locked.
 *
 * Runs from screen off ([onLocked]) to unlock ([onUnlocked]), told by
 * [StandbyMonitor]. It only reacts to session callbacks: no polling.
 */
object LockedPlayback {

    private const val TAG = "LockedPlayback"

    private val handler = Handler(Looper.getMainLooper())
    private var sessions: MediaSessionManager? = null
    private var controllers: List<MediaController> = emptyList()
    private var watching = false

    /** Packages that played since the lock. */
    private val played = mutableSetOf<String>()

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        track(list.orEmpty())
    }

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = check()
        override fun onMetadataChanged(metadata: MediaMetadata?) = check()
    }

    /** The screen went off: from now until unlock, remember who plays. */
    fun onLocked(context: Context) {
        if (watching) return
        played.clear()
        if (!NowPlaying.hasAccess(context)) return
        val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        val listener = ComponentName(context, MediaListenerService::class.java)
        try {
            manager.addOnActiveSessionsChangedListener(sessionsChanged, listener, handler)
            sessions = manager
            watching = true
            track(manager.getActiveSessions(listener))
        } catch (e: SecurityException) {
            Log.w(TAG, "no notification access", e)
        }
    }

    /** Unlocked: start afresh next time. */
    fun onUnlocked() {
        played.clear()
        if (!watching) return
        watching = false
        runCatching { sessions?.removeOnActiveSessionsChangedListener(sessionsChanged) }
        sessions = null
        track(emptyList())
    }

    /** A player [NowPlaying] saw playing (e.g. started from standby). */
    fun mark(pkg: String) {
        if (watching) played += pkg
    }

    /** [pkg] played since the lock, so it stays on the tile when paused. */
    fun playedSinceLock(pkg: String): Boolean = pkg in played

    private fun track(list: List<MediaController>) {
        controllers.forEach { runCatching { it.unregisterCallback(callback) } }
        controllers = list
        list.forEach { it.registerCallback(callback, handler) }
        check()
    }

    private fun check() {
        controllers.filter { it.playbackState?.state == PlaybackState.STATE_PLAYING }.forEach { played += it.packageName }
    }
}
