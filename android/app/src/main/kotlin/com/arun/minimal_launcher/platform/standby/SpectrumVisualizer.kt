package com.arun.minimal_launcher.platform.standby

import android.media.audiofx.Visualizer
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * The levels of what the phone plays, for the "Deck" standby style: a 10-band
 * graphic EQ readout (31 Hz to 16 kHz, one octave each) and a left/right pair
 * for the VU meters. Android's [Visualizer] on the output mix (session 0),
 * 20 to 35 readings a second. Only used while the deck is up; the glow
 * style's [BeatVisualizer] is never on at the same time.
 *
 * Each band is its octave's power in dB, tilted +3 dB per octave (music has
 * far less energy up top), against a slowly falling running peak, so quiet
 * and loud songs both fill the display. Values are 0-1; smoothing, peak
 * caps and needle ballistics happen on the Dart side at the display's rate.
 *
 * The output mix is mono here, so the meters' left and right are the same
 * signal leaned towards the low end (left) and the high end (right): they
 * move together but not in lockstep, as real stereo meters do.
 *
 * Needs RECORD_AUDIO, like the beat pulse; nothing is recorded or kept.
 */
class SpectrumVisualizer(private val context: Context, private val onFrame: (Map<String, Any>) -> Unit) {

    private var visualizer: Visualizer? = null
    private val main = Handler(Looper.getMainLooper())

    /** The waveform's RMS (0-1) from the last capture. */
    @Volatile private var rms = 0.0

    /** Running peak of the loudest band, in dB; falls slowly. */
    private var peakDb = 30.0

    fun start(): Boolean {
        if (visualizer != null) return true
        if (!BeatVisualizer.hasPermission(context)) return false
        return try {
            val v = Visualizer(0)
            v.enabled = false
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(2048)
            runCatching { v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED }
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(vis: Visualizer?, waveform: ByteArray?, rate: Int) {
                        if (waveform != null) rms = rmsOf(waveform)
                    }

                    override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, rate: Int) {
                        if (fft != null) analyse(fft, rate)
                    }
                },
                Visualizer.getMaxCaptureRate(),
                true,
                true,
            )
            v.enabled = true
            visualizer = v
            true
        } catch (e: Exception) {
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
        rms = 0.0
        peakDb = 30.0
    }

    private fun rmsOf(wave: ByteArray): Double {
        var sum = 0.0
        for (b in wave) {
            val s = ((b.toInt() and 0xFF) - 128) / 128.0
            sum += s * s
        }
        return sqrt(sum / wave.size)
    }

    private fun analyse(fft: ByteArray, rate: Int) {
        val n = fft.size / 2
        if (n < 8) return
        val hzPerBin = rate / 1000.0 / fft.size
        val bands = DoubleArray(CENTERS.size)
        var loudest = -100.0
        for ((i, c) in CENTERS.withIndex()) {
            val lo = c / SQRT2
            val hi = c * SQRT2
            var from = max(1, (lo / hzPerBin).toInt())
            var to = min(n - 1, (hi / hzPerBin).toInt())
            // Low octaves narrower than a bin: the bin they fall in.
            if (to < from) {
                from = min(n - 1, max(1, (c / hzPerBin).toInt()))
                to = from
            }
            var power = 0.0
            for (k in from..to) {
                val m = hypot(fft[2 * k].toDouble(), fft[2 * k + 1].toDouble())
                power += m * m
            }
            power /= (to - from + 1)
            val db = 10 * log10(power + 1e-3) + i * TILT_DB
            bands[i] = db
            loudest = max(loudest, db)
        }
        // Silence: everything at rest.
        if (rms < SILENCE) {
            post(DoubleArray(CENTERS.size), 0.0, 0.0)
            return
        }
        // Follow a louder song at once, a quieter one over a few seconds.
        peakDb = if (loudest > peakDb) loudest else peakDb - FALL_DB
        peakDb = max(peakDb, MIN_PEAK_DB)
        val floor = peakDb - RANGE_DB
        val levels = DoubleArray(bands.size) { ((bands[it] - floor) / RANGE_DB).coerceIn(0.0, 1.0) }

        val low = (levels[0] + levels[1] + levels[2] + levels[3]) / 4
        val high = (levels[6] + levels[7] + levels[8] + levels[9]) / 4
        // RMS of normalised audio sits near 0.1-0.4: in dBFS for the meter,
        // the VU's 0 at about -12 dBFS.
        val vu = (20 * log10(rms + 1e-6) + 12 + 20) / 23 // -20 VU..+3 VU -> 0..1
        val lean = (low - high) * 0.12
        post(levels, (vu + lean).coerceIn(0.0, 1.0), (vu - lean).coerceIn(0.0, 1.0))
    }

    private fun post(levels: DoubleArray, left: Double, right: Double) {
        val list = levels.toList()
        main.post { onFrame(mapOf("bands" to list, "left" to left, "right" to right)) }
    }

    companion object {
        private const val TAG = "SpectrumVisualizer"
        private val CENTERS = doubleArrayOf(31.5, 63.0, 125.0, 250.0, 500.0, 1_000.0, 2_000.0, 4_000.0, 8_000.0, 16_000.0)
        private val SQRT2 = 2.0.pow(0.5)
        private const val TILT_DB = 3.0
        private const val RANGE_DB = 36.0
        private const val FALL_DB = 0.08
        private const val MIN_PEAK_DB = 20.0
        private const val SILENCE = 0.004
    }
}
