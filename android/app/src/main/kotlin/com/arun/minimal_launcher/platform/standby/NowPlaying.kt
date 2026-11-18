package com.arun.minimal_launcher.platform.standby

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.arun.minimal_launcher.platform.HiddenNotifications
import android.util.Log
import android.view.KeyEvent
import java.io.ByteArrayOutputStream

/**
 * Lets Android hand us other apps' media sessions
 * ([MediaSessionManager.getActiveSessions] needs an enabled notification
 * listener). The only notifications it acts on are hidden apps', when the
 * user turned those off ([HiddenNotifications]).
 */
class MediaListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        HiddenNotifications.listener = this
        HiddenNotifications.sweep(this)
    }

    override fun onListenerDisconnected() {
        if (HiddenNotifications.listener === this) HiddenNotifications.listener = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        HiddenNotifications.onPosted(this, sbn)
    }
}

/**
 * What's playing on the phone (any app: Spotify, YouTube Music, a browser…),
 * for the standby clock's now-playing tile, and its controls.
 *
 * Needs notification access ([hasAccess]). Watches only while [start]ed: the
 * clock starts it when shown and stops it when hidden.
 */
class NowPlaying(
    private val context: Context,
    /**
     * Standby: a paused song shows only if it played since the lock. Off for
     * the home screen's music widget: any paused song shows, as long as its
     * session lasts.
     */
    private val onlySinceLock: Boolean = true,
    private val onLevels: (Map<String, Any>) -> Unit = {},
    private val onChange: (Map<String, Any?>?) -> Unit,
) {

    private val handler = Handler(Looper.getMainLooper())
    private val sessions = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val listener = ComponentName(context, MediaListenerService::class.java)

    private var controllers: List<MediaController> = emptyList()
    private var watching = false

    /** The art last pushed, so it's sent again only when the track changes. */
    private var sentArtKey: String? = null

    /**
     * The song on the tile, held on to until unlock even if its player drops
     * the session or stops reporting it after a pause (some do), so it can be
     * played again from standby. Kept across showings.
     */
    private var held: MediaController? = null
    private var heldGone = false

    /** [held]'s last description and cover, for when the session is gone. */
    private var heldMap: Map<String, Any?>? = null
    private var heldArt: ByteArray? = null

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        track(list.orEmpty())
        push()
    }

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = push()
        override fun onMetadataChanged(metadata: MediaMetadata?) = push()
        override fun onSessionDestroyed() = push()
        override fun onSessionEvent(event: String, extras: android.os.Bundle?) = levelsEvent(event, extras)
    }

    /** On [held] only, when it isn't among the active sessions. */
    private val heldCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = push()
        override fun onMetadataChanged(metadata: MediaMetadata?) = push()
        override fun onSessionDestroyed() {
            heldGone = true
            push()
        }
        override fun onSessionEvent(event: String, extras: android.os.Bundle?) = levelsEvent(event, extras)
    }

    fun start() {
        if (watching || !hasAccess(context)) return
        try {
            sessions.addOnActiveSessionsChangedListener(sessionsChanged, listener, handler)
            watching = true
            track(sessions.getActiveSessions(listener))
        } catch (e: SecurityException) {
            Log.w("NowPlaying", "no notification access", e)
        }
    }

    fun stop() {
        if (!watching) return
        watching = false
        runCatching { sessions.removeOnActiveSessionsChangedListener(sessionsChanged) }
        track(emptyList())
        sentArtKey = null
    }

    private fun track(list: List<MediaController>) {
        controllers.forEach { runCatching { it.unregisterCallback(callback) } }
        held?.let { h -> runCatching { h.unregisterCallback(heldCallback) } }
        controllers = list
        list.forEach { it.registerCallback(callback, handler) }
        // The same session again: use the fresh controller.
        held?.let { h -> list.firstOrNull { it.sessionToken == h.sessionToken }?.let { held = it } }
        if (watching) held?.takeIf { h -> list.none { it.sessionToken == h.sessionToken } }
            ?.let { runCatching { it.registerCallback(heldCallback, handler) } }
    }

    private fun push() {
        onChange(current(includeArt = false))
        if (levelsWanted && levelsSource()?.sessionToken != levelsFrom?.sessionToken) askLevels()
    }

    // ---- A connected laptop's output levels (Phone Link), for the deck's meters ----

    private var levelsWanted = false

    /** The laptop session last asked for levels. */
    private var levelsFrom: MediaController? = null

    private val renewLevels = object : Runnable {
        override fun run() {
            askLevels()
            handler.postDelayed(this, LEVELS_RENEW_MS)
        }
    }

    /**
     * While [on], asks the shown track's link app for the computer's output levels
     * (they arrive through [onLevels]), renewing the request every few seconds as
     * Phone Link expects; the phone's own Visualizer can't hear a laptop.
     */
    fun listenLevels(on: Boolean) {
        if (on == levelsWanted) return
        levelsWanted = on
        handler.removeCallbacks(renewLevels)
        if (on) {
            renewLevels.run()
        } else {
            levelsFrom?.let { sendListen(it, false) }
            levelsFrom = null
        }
    }

    /** The shown track, when it plays on a connected computer. */
    private fun levelsSource(): MediaController? =
        if (!watching) null else (active() ?: held)?.takeIf { isConnected(it) && playing(it) }

    private fun askLevels() {
        val c = levelsSource()
        levelsFrom?.takeIf { it.sessionToken != c?.sessionToken }?.let { sendListen(it, false) }
        levelsFrom = c
        c?.let { sendListen(it, true) }
    }

    private fun sendListen(c: MediaController, on: Boolean) {
        runCatching { c.sendCommand(LEVELS_LISTEN, android.os.Bundle().apply { putBoolean("listen", on) }, null) }
    }

    private fun levelsEvent(event: String, extras: android.os.Bundle?) {
        if (event != LEVELS_EVENT || !levelsWanted || extras == null) return
        val bands = extras.getDoubleArray("bands") ?: return
        onLevels(mapOf("bands" to bands.toList(), "left" to extras.getDouble("left"), "right" to extras.getDouble("right")))
    }

    private fun playing(c: MediaController) = c.playbackState?.state == PlaybackState.STATE_PLAYING

    /**
     * The session to show, best first: playing on this phone, playing on a
     * connected computer (through a link app, see [CONNECTED]), then paused
     * ones the same way, but only those that played since the phone was
     * locked ([LockedPlayback]): paused on the lock screen or in standby, it
     * stays until unlock; paused before locking, it isn't shown. Within each,
     * the most recent. Null when nothing is.
     */
    private fun active(): MediaController? {
        val live = controllers.filter { it.playbackState?.state.let { s -> s != null && s in SHOWN } && it.metadata != null }
        live.filter(::playing).forEach { LockedPlayback.mark(it.packageName) }
        val kept = live.filter { !playing(it) && (!onlySinceLock || LockedPlayback.playedSinceLock(it.packageName)) }
        return live.firstOrNull { playing(it) && !isConnected(it) }
            ?: live.firstOrNull { playing(it) }
            ?: kept.firstOrNull { !isConnected(it) }
            ?: kept.firstOrNull()
    }

    /**
     * [held], while it may still be shown: it played since the lock. A
     * computer's track goes with its session (the link is gone).
     */
    private fun stillHeld(): MediaController? {
        val h = held ?: return null
        val inList = controllers.any { it.sessionToken == h.sessionToken }
        val expired = if (onlySinceLock) !LockedPlayback.playedSinceLock(h.packageName) else heldGone
        if (expired || (isConnected(h) && (heldGone || !inList))) {
            release()
            return null
        }
        return h
    }

    private fun hold(c: MediaController) {
        if (held?.sessionToken == c.sessionToken) {
            held = c
            return
        }
        release()
        held = c
        heldGone = false
    }

    private fun release() {
        held?.let { h -> runCatching { h.unregisterCallback(heldCallback) } }
        held = null
        heldGone = false
        heldMap = null
        heldArt = null
    }

    /** Media of another device, relayed by a link app, not this phone's own. */
    private fun isConnected(c: MediaController) =
        c.packageName in CONNECTED || runCatching { c.extras?.getBoolean("phonelink.remote") }.getOrNull() == true

    /** The computer's name, when the link app says it (Phone Link does). */
    private fun deviceName(c: MediaController): String? =
        runCatching { c.extras?.getString("deviceName") }.getOrNull()?.takeIf { it.isNotBlank() }

    /**
     * {title, artist, album, app, package, connected, durationMs, positionMs, speed,
     * playing, canPrevious, canNext, canSeek, artKey, art: ByteArray?, hasArt};
     * `art` only when [includeArt] or the track changed since last sent.
     *
     * The active session ([active]); else the song held since it played
     * ([held]), shown paused, from its last description if its session is
     * gone, until the phone is unlocked.
     */
    fun current(includeArt: Boolean = true): Map<String, Any?>? {
        active()?.let { c ->
            describe(c, includeArt)?.let {
                hold(c)
                remember(it)
                return it
            }
        }
        val h = stillHeld() ?: return null
        if (!heldGone) describe(h, includeArt, fromHold = true)?.let {
            remember(it)
            return it
        }
        val last = heldMap ?: return null
        val sendArt = includeArt || last["artKey"] != sentArtKey
        sentArtKey = last["artKey"] as String?
        // Its session is gone: play/skip go by media key, which can't seek.
        return last + mapOf("playing" to false, "speed" to 0.0, "canSeek" to false, "art" to if (sendArt) heldArt else null, "hasArt" to sendArt)
    }

    private fun remember(map: Map<String, Any?>) {
        if (map["hasArt"] == true) heldArt = map["art"] as ByteArray?
        heldMap = map - "art"
    }

    /** [fromHold]: the held song, not an active session: keep its last position if it reports none. */
    private fun describe(c: MediaController, includeArt: Boolean, fromHold: Boolean = false): Map<String, Any?>? {
        val meta = c.metadata ?: return null
        val state = c.playbackState

        val title = meta.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: return null
        val artist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
        val album = meta.getString(MediaMetadata.METADATA_KEY_ALBUM)
        val playing = state?.state == PlaybackState.STATE_PLAYING

        // Where it is right now, not at the session's last update. A stopped
        // player may report 0: keep where it was.
        var position = state?.position ?: 0
        if (playing && state != null && state.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - state.lastPositionUpdateTime) * state.playbackSpeed).toLong()
        }
        val heldPosition = (heldMap?.get("positionMs") as? Long)
        if (fromHold && position <= 0 && heldMap?.get("title") == title && heldPosition != null) position = heldPosition
        val duration = meta.getLong(MediaMetadata.METADATA_KEY_DURATION)
        if (duration > 0) position = position.coerceIn(0, duration)

        // Apps often send the cover a moment after the title: part of the key.
        val artKey = "${c.packageName}|$title|$artist|$album|${artSource(meta)}"
        val sendArt = includeArt || artKey != sentArtKey
        sentArtKey = artKey

        // A stopped player may offer no actions: play and skip go by media key.
        val actions = state?.actions ?: 0L
        val noActions = actions == 0L
        return mapOf(
            "title" to title,
            "artist" to artist,
            "album" to album,
            "package" to c.packageName,
            "connected" to isConnected(c),
            // Playing on a laptop: its name, not the link app's.
            "app" to ((if (isConnected(c)) deviceName(c) else null) ?: appName(c.packageName)),
            "durationMs" to duration.takeIf { it > 0 },
            "positionMs" to position.coerceAtLeast(0),
            "speed" to if (playing) (state?.playbackSpeed ?: 1f).toDouble() else 0.0,
            "playing" to playing,
            "canPrevious" to (noActions || actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L),
            "canNext" to (noActions || actions and PlaybackState.ACTION_SKIP_TO_NEXT != 0L),
            "canSeek" to (actions and PlaybackState.ACTION_SEEK_TO != 0L && duration > 0),
            "artKey" to artKey,
            "art" to if (sendArt) art(meta) else null,
            "hasArt" to sendArt,
        )
    }

    /**
     * play | pause | toggle | next | previous | seek (with [positionMs]), on
     * the song shown. If its player dropped the session, by media key (it
     * goes to the app that played last).
     */
    fun command(name: String, positionMs: Long?): Boolean {
        val c = active() ?: stillHeld()
        if (c == null || (c === held && heldGone)) return mediaKey(name)
        val t = c.transportControls
        when (name) {
            "play" -> t.play()
            "pause" -> t.pause()
            "toggle" -> if (playing(c)) t.pause() else t.play()
            "next" -> t.skipToNext()
            "previous" -> t.skipToPrevious()
            "seek" -> t.seekTo(positionMs ?: return false)
            else -> return false
        }
        return true
    }

    /**
     * The volume of what's shown, {current, max}: its session's own (a
     * computer's, through a link app, or the phone's music volume), else the
     * phone's music volume.
     */
    fun volume(): Map<String, Int> {
        laptopVolume()?.let { (_, v) -> return mapOf("current" to v, "max" to 100) }
        volumeSession()?.playbackInfo?.let { return mapOf("current" to it.currentVolume, "max" to it.maxVolume) }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return mapOf(
            "current" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
            "max" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
        )
    }

    /** Sets [volume]'s level, quietly (no system volume panel). */
    fun setVolume(level: Int): Boolean = runCatching {
        laptopVolume()?.first?.let { laptop: MediaController ->
            laptop.sendCommand(VOLUME_SET, android.os.Bundle().apply { putInt("volume", level.coerceIn(0, 100)) }, null)
            return@runCatching true
        }
        val c = volumeSession()
        if (c != null) {
            c.setVolumeTo(level.coerceIn(0, c.playbackInfo?.maxVolume ?: level), 0)
        } else {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, level.coerceIn(0, audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)), 0)
        }
        true
    }.getOrDefault(false)

    /**
     * The shown song when it plays on a computer whose link app shares the
     * computer's volume (Phone Link: extra [VOLUME_EXTRA], 0-100, and the
     * [VOLUME_SET] command), with that volume; null otherwise.
     */
    private fun laptopVolume(): Pair<MediaController, Int>? {
        val c = (active() ?: stillHeld())?.takeIf { isConnected(it) && !(it === held && heldGone) } ?: return null
        val v = runCatching { c.extras?.takeIf { it.containsKey(VOLUME_EXTRA) }?.getInt(VOLUME_EXTRA) }.getOrNull()
            ?: return null
        return c to v
    }

    /** The shown song's session, if its volume can be changed. */
    private fun volumeSession(): MediaController? {
        val c = (active() ?: stillHeld())?.takeIf { !(it === held && heldGone) } ?: return null
        val info = c.playbackInfo ?: return null
        return c.takeIf { info.volumeControl != android.media.VolumeProvider.VOLUME_CONTROL_FIXED && info.maxVolume > 0 }
    }

    private fun mediaKey(name: String): Boolean {
        val code = when (name) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "toggle" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return false
        }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        return true
    }

    private fun appName(pkg: String): String? = runCatching {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    }.getOrNull()

    private fun artBitmap(meta: MediaMetadata): Bitmap? = BITMAP_KEYS.firstNotNullOfOrNull { meta.getBitmap(it) }

    private fun artUri(meta: MediaMetadata): String? = URI_KEYS.firstNotNullOfOrNull { meta.getString(it) }

    /** Which cover the track has, without decoding it. */
    private fun artSource(meta: MediaMetadata): String =
        artBitmap(meta)?.let { "${it.width}x${it.height}#${it.generationId}" } ?: artUri(meta) ?: "-"

    /** The cover, at most [ART_PX] square, as JPEG. */
    private fun art(meta: MediaMetadata): ByteArray? {
        val bitmap = artBitmap(meta) ?: artUri(meta)?.let(::load) ?: return null
        return runCatching {
            val scale = ART_PX.toFloat() / maxOf(bitmap.width, bitmap.height)
            val small = if (scale < 1f) {
                Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
            } else bitmap
            ByteArrayOutputStream().use { out ->
                small.compress(Bitmap.CompressFormat.JPEG, 95, out)
                out.toByteArray()
            }
        }.getOrNull()
    }

    /** Only content/file URIs (no network on the main thread). */
    private fun load(uri: String): Bitmap? = runCatching {
        val u = Uri.parse(uri)
        if (u.scheme != "content" && u.scheme != "file" && u.scheme != "android.resource") return null
        context.contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it) }
    }.getOrNull()

    companion object {
        /** Sharp on a ~3x screen up to ~240dp; sent only when the track changes. */
        private const val ART_PX = 720

        /** Phone Link's laptop session: ask for levels (a 10 s lease), and the levels. */
        private const val LEVELS_LISTEN = "phonelink.levels.listen"
        private const val LEVELS_EVENT = "phonelink.levels"
        private const val LEVELS_RENEW_MS = 4_000L

        /** Phone Link's laptop session: the laptop's output volume (0-100), and setting it. */
        private const val VOLUME_EXTRA = "phonelink.volume"
        private const val VOLUME_SET = "phonelink.volume.set"

        /**
         * Apps that relay a computer's players to the phone: what they play
         * isn't the phone's own, so the phone's wins when both play.
         */
        private val CONNECTED = setOf(
            "com.arun.phonelink", // Phone Link (this laptop)
            "org.kde.kdeconnect_tp", // KDE Connect / GSConnect
            "com.microsoft.appmanager", // Link to Windows
            "com.samsung.android.mdx", // Samsung Link to Windows
        )

        private val BITMAP_KEYS = listOf(
            MediaMetadata.METADATA_KEY_ALBUM_ART,
            MediaMetadata.METADATA_KEY_ART,
            MediaMetadata.METADATA_KEY_DISPLAY_ICON,
        )

        private val URI_KEYS = listOf(
            MediaMetadata.METADATA_KEY_ALBUM_ART_URI,
            MediaMetadata.METADATA_KEY_ART_URI,
            MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI,
        )

        private val SHOWN = setOf(
            PlaybackState.STATE_PLAYING,
            PlaybackState.STATE_PAUSED,
            PlaybackState.STATE_BUFFERING,
            PlaybackState.STATE_CONNECTING,
            PlaybackState.STATE_SKIPPING_TO_NEXT,
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS,
            PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM,
        )

        /** Notification access is on for this app. */
        fun hasAccess(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(context, MediaListenerService::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        /** Where notification access is turned on (straight to this app on 30+). */
        fun openAccessSettings(context: Context) {
            val me = ComponentName(context, MediaListenerService::class.java)
            val direct = Intent("android.settings.NOTIFICATION_LISTENER_DETAIL_SETTINGS")
                .putExtra("android.provider.extra.NOTIFICATION_LISTENER_COMPONENT_NAME", me.flattenToString())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val list = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (android.os.Build.VERSION.SDK_INT >= 30 && runCatching { context.startActivity(direct) }.isSuccess) return
            runCatching { context.startActivity(list) }
        }
    }
}
