package cloud.orbital8.gold_card

import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {

    companion object {
        private const val ACCELEROMETER_CHANNEL = "cloud.orbital8.gold_card/accelerometer"
        private const val DEVICE_CHANNEL = "cloud.orbital8.gold_card/device"
        // ~33.4° ergonomic wrist tilt (9.80665 * sin(33.4°)) maps to 1.0 normalized unit.
        private const val FULL_TILT_METERS_PER_SEC_SQ = 5.4
    }

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isListeningSensor: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        super.onCreate(savedInstanceState)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        enableImmersiveLandscape()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACCELEROMETER_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                startSensorUpdates()
            }

            override fun onCancel(arguments: Any?) {
                stopSensorUpdates()
                eventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccelerometer" -> {
                    result.success(accelerometer != null)
                }
                "lockLandscape" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    enableImmersiveLandscape()
                    result.success(true)
                }
                "getScreenRotation" -> {
                    result.success(currentScreenRotation())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        enableImmersiveLandscape()
        if (eventSink != null) {
            startSensorUpdates()
        }
    }

    override fun onPause() {
        stopSensorUpdates()
        super.onPause()
    }

    override fun onDestroy() {
        stopSensorUpdates()
        eventSink = null
        super.onDestroy()
    }

    private fun startSensorUpdates() {
        if (isListeningSensor) return
        val sensor = accelerometer ?: return
        val registered = sensorManager?.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_GAME
        ) ?: false
        isListeningSensor = registered
    }

    private fun stopSensorUpdates() {
        if (!isListeningSensor) return
        sensorManager?.unregisterListener(this)
        isListeningSensor = false
    }

    private fun currentScreenRotation(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_90
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay?.rotation ?: Surface.ROTATION_90
        }
    }

    private fun enableImmersiveLandscape() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val sink = eventSink ?: return

        val ax = event.values[0].toDouble()
        val ay = event.values[1].toDouble()
        val az = event.values[2].toDouble()

        // Project device-frame proper acceleration onto Landscape Screen coordinates:
        // screenHorizontal: < 0 when tilted left, > 0 when tilted right along landscape width.
        // screenVertical: tilt along landscape height (top <-> bottom).
        val rotation = currentScreenRotation()
        val projectedHorizontal: Double
        val projectedVertical: Double

        when (rotation) {
            Surface.ROTATION_90 -> {
                projectedHorizontal = ay
                projectedVertical = ax
            }
            Surface.ROTATION_270 -> {
                projectedHorizontal = -ay
                projectedVertical = -ax
            }
            Surface.ROTATION_180 -> {
                projectedHorizontal = ax
                projectedVertical = -ay
            }
            else -> {
                projectedHorizontal = -ax
                projectedVertical = ay
            }
        }

        val screenHorizontal = (projectedHorizontal / FULL_TILT_METERS_PER_SEC_SQ).coerceIn(-2.5, 2.5)
        val screenVertical = (projectedVertical / FULL_TILT_METERS_PER_SEC_SQ).coerceIn(-2.5, 2.5)

        sink.success(
            mapOf(
                "x" to ax,
                "y" to ay,
                "z" to az,
                "screenHorizontal" to screenHorizontal,
                "screenVertical" to screenVertical
            )
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // No-op.
    }
}
