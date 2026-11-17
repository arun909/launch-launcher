package com.arun.minimal_launcher.platform.standby

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper

/**
 * The proximity sensor, so the standby clock never lights up (or stays lit)
 * in a pocket or face down. Phones without one count as never covered.
 */
object Proximity {

    private const val TIMEOUT_MS = 600L

    /** Whether [event] means something is right over the sensor. */
    fun isNear(sensor: Sensor, event: SensorEvent): Boolean =
        event.values[0] < minOf(sensor.maximumRange, 5f)

    fun sensor(context: Context): Sensor? =
        (context.getSystemService(Context.SENSOR_SERVICE) as SensorManager).getDefaultSensor(Sensor.TYPE_PROXIMITY)

    /** One reading; [done] gets false if none comes in time. */
    fun check(context: Context, done: (near: Boolean) -> Unit) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sensor(context) ?: return done(false)
        val handler = Handler(Looper.getMainLooper())
        var answered = false
        lateinit var listener: SensorEventListener
        fun answer(near: Boolean) {
            if (answered) return
            answered = true
            manager.unregisterListener(listener)
            handler.removeCallbacksAndMessages(null)
            done(near)
        }
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) = answer(isNear(sensor, event))
            override fun onAccuracyChanged(s: Sensor?, accuracy: Int) {}
        }
        if (!manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)) return done(false)
        handler.postDelayed({ answer(false) }, TIMEOUT_MS)
    }
}
