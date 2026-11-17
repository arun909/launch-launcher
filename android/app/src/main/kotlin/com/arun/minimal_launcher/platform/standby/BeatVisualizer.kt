package com.arun.minimal_launcher.platform.standby

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * The hits in what the phone is playing, per band (bass, mids, treble), for
 * the standby clock's background glow, where each band pulses its own patch
 * of the screen. Android's [Visualizer] on the output mix (session 0) gives
 * the sound's spectrum 20 to 35 times a second, depending on the phone.
 *
 * Each band finds its hits by spectral flux, the usual onset detector: how
 * much louder its frequencies got since the last reading, only rises
 * counted. A hit is a sharp rise of that flux above the band's own adaptive
 * threshold (its mean plus a few deviations over the last ~1.5 s), so it
 * keeps up with quiet and loud songs alike, and held notes or a steady loud
 * bass don't count. After a hit, a short pause scaled to that band's own
 * spacing keeps one hit from firing twice.
 *
 * Needs RECORD_AUDIO (Android asks it of any visualizer), but nothing is
 * recorded: only the spectrum of the phone's own output, never the
 * microphone, and nothing is kept. Some phones refuse session 0; then
 * [start] returns false and the glow stays still. Media on a connected
 * laptop isn't heard here.
 */
class BeatVisualizer(private val context: Context, private val onFrame: (Map<String, Any>) -> Unit) {

    private var visualizer: Visualizer? = null

    private val main = Handler(Looper.getMainLooper())

    /** The last reading's log magnitudes, per bin. */
    private var previous: DoubleArray? = null

    /** Bass, mids, treble. */
    private val bands = listOf(
        Band(0, 0.0, 180.0, minGapMs = 200, maxGapMs = 350),
        Band(1, 180.0, 2_000.0, minGapMs = 150, maxGapMs = 300),
        Band(2, 2_000.0, 8_000.0, minGapMs = 110, maxGapMs = 250),
    )

    fun start(): Boolean {
        if (visualizer != null) return true
        if (!hasPermission(context)) return false
        return try {
            val v = Visualizer(0)
            v.enabled = false
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            runCatching { v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED }
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(vis: Visualizer?, waveform: ByteArray?, rate: Int) {}
                    override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, rate: Int) {
                        if (fft != null) analyse(fft, rate)
                    }
                },
                Visualizer.getMaxCaptureRate(),
                false,
                true,
            )
            v.enabled = true
            visualizer = v
            Log.i(TAG, "listening (capture ${v.captureSize}, ${Visualizer.getMaxCaptureRate() / 1000} Hz)")
            true
        } catch (e: Exception) {
            // Not allowed on this phone, or the audio system is busy.
            Log.w(TAG, "visualizer unavailable", e)
            false
        }
    }

    fun stop() {
        visualizer?.let { v ->
            runCatching { v.enabled = false }
            runCatching { v.release() }
        }
        visualizer = null
        previous = null
        bands.forEach { it.reset() }
    }

    /**
     * [fft]: Visualizer's layout (real/imaginary pairs, bin 0 and n/2 first);
     * [rate]: sampling rate in mHz.
     */
    private fun analyse(fft: ByteArray, rate: Int) {
        val n = fft.size / 2
        if (n < 8) return
        val hzPerBin = rate / 1000.0 / fft.size
        val top = min(n - 1, (bands.last().highHz / hzPerBin).toInt())
        val mags = DoubleArray(top + 1)
        var level = 0.0
        for (k in 1..top) {
            val m = hypot(fft[2 * k].toDouble(), fft[2 * k + 1].toDouble())
            mags[k] = ln(1 + m)
            level += m
        }
        val prev = previous
        previous = mags
        // Silence (paused, between tracks): start afresh when the sound comes back.
        if (level / top < SILENCE) {
            bands.forEach { it.quiet() }
            return
        }
        if (prev == null) return

        // Spectral flux per band: how much louder its bins got, only rises counted.
        val sums = DoubleArray(bands.size)
        val counts = IntArray(bands.size)
        for (k in 1..top) {
            val hz = k * hzPerBin
            val b = bands.indexOfFirst { hz < it.highHz }
            if (b < 0) continue
            sums[b] += max(0.0, mags[k] - prev[k])
            counts[b]++
        }
        val now = SystemClock.elapsedRealtime()
        for ((i, band) in bands.withIndex()) {
            if (counts[i] == 0) continue
            val strength = band.feed(sums[i] / counts[i], now) ?: continue
            main.post { onFrame(mapOf("beat" to true, "band" to band.index, "strength" to strength)) }
        }
    }

    /** One band's hit detector. */
    private class Band(
        val index: Int,
        val lowHz: Double,
        val highHz: Double,
        private val minGapMs: Long,
        private val maxGapMs: Long,
    ) {
        /** Recent onset strengths (the threshold's window). */
        private val history = ArrayDeque<Double>()

        /** Whether the last reading was already above the threshold. */
        private var above = false
        private var last = 0L

        /** Recent gaps between hits, for this band's spacing. */
        private val gaps = ArrayDeque<Long>()

        fun reset() {
            quiet()
            gaps.clear()
        }

        fun quiet() {
            history.clear()
            above = false
        }

        /** This reading's flux; a hit's strength (0-1), or null. */
        fun feed(onset: Double, now: Long): Double? {
            val mean = if (history.isEmpty()) onset else history.average()
            val sd = if (history.size < 2) 0.0 else sqrt(history.sumOf { (it - mean) * (it - mean) } / history.size)
            val peak = history.maxOrNull() ?: onset
            history.addLast(onset)
            if (history.size > WINDOW) history.removeFirst()
            if (history.size < WINDOW / 3) return null // Still learning this song.

            val threshold = mean + SENSITIVITY * sd + MIN_FLUX
            val spacing = gaps.sorted().let { if (it.isEmpty()) 0L else it[it.size / 2] }
            val pause = max(minGapMs, (spacing * 0.45).toLong()).coerceAtMost(maxGapMs)
            val rising = onset > threshold && !above
            above = onset > threshold
            if (!rising || now - last < pause) return null

            val gap = now - last
            if (gap in 120L..1500L) {
                gaps.addLast(gap)
                if (gaps.size > 8) gaps.removeFirst()
            }
            last = now
            return ((onset - threshold) / max(1e-6, max(peak, onset) - threshold) * 0.6 + 0.4).coerceIn(0.0, 1.0)
        }
    }

    companion object {
        private const val TAG = "BeatVisualizer"

        /** Readings in the threshold's window: ~1.5 s at the usual 35 a second. */
        private const val WINDOW = 50

        /** Deviations above the mean a hit must rise. */
        private const val SENSITIVITY = 1.3

        /** A floor, so near-silent hiss never counts. */
        private const val MIN_FLUX = 0.04
        private const val SILENCE = 0.25

        fun hasPermission(context: Context) =
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }
}
