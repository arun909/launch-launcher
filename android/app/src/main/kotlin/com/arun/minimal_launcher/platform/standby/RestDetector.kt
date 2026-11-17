package com.arun.minimal_launcher.platform.standby

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Tells when the phone has been lying still (on a table or a stand) for
 * [STILL_MS]: the accelerometer reads steady gravity, with almost no change
 * from one reading to the next. A phone in a hand never is that still.
 */
class RestDetector(context: Context, private val onRest: () -> Unit) : SensorEventListener {

    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor: Sensor? = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var stillSince = 0L
    private var last: FloatArray? = null
    private var fired = false

    val available: Boolean get() = sensor != null

    fun start() {
        stillSince = 0L
        last = null
        fired = false
        sensor?.let { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    fun stop() = manager.unregisterListener(this)

    override fun onSensorChanged(event: SensorEvent) {
        if (fired) return
        val (x, y, z) = Triple(event.values[0], event.values[1], event.values[2])
        val magnitude = sqrt(x * x + y * y + z * z)
        val previous = last
        last = floatArrayOf(x, y, z)
        val now = SystemClock.elapsedRealtime()
        val steady = abs(magnitude - SensorManager.GRAVITY_EARTH) < GRAVITY_SLACK &&
            previous != null &&
            abs(x - previous[0]) < JITTER && abs(y - previous[1]) < JITTER && abs(z - previous[2]) < JITTER
        if (!steady) {
            stillSince = 0L
            return
        }
        if (stillSince == 0L) stillSince = now
        if (now - stillSince >= STILL_MS) {
            fired = true
            stop()
            onRest()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private companion object {
        const val STILL_MS = 800L
        const val GRAVITY_SLACK = 0.6f
        const val JITTER = 0.12f
    }
}
