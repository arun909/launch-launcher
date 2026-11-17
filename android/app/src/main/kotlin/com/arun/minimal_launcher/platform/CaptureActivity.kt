package com.arun.minimal_launcher.platform

import android.Manifest
import android.animation.ObjectAnimator
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File

/**
 * The instant widget's camera: a live viewfinder and one shutter. A tap
 * takes the photo into [EXTRA_OUTPUT] and returns at once (no review
 * screen); tap the preview to focus, pinch to zoom. Black and white, like
 * the widget.
 *
 * Results: RESULT_OK (the photo is in the file), RESULT_CANCELED, or
 * [RESULT_DENIED] if the camera permission was refused.
 */
class CaptureActivity : ComponentActivity() {

    private lateinit var output: File
    private lateinit var controller: LifecycleCameraController
    private lateinit var preview: PreviewView
    private lateinit var shutter: ShutterView
    private var taking = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        output = File(intent.getStringExtra(EXTRA_OUTPUT) ?: return finishWith(RESULT_CANCELED))
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        preview = PreviewView(this).apply {
            implementationMode = PreviewView.ImplementationMode.PERFORMANCE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        root.addView(preview, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        val dp = resources.displayMetrics.density
        shutter = ShutterView(this).apply { setOnClickListener { take() } }
        root.addView(shutter, FrameLayout.LayoutParams((76 * dp).toInt(), (76 * dp).toInt(), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
        val close = CloseView(this).apply { setOnClickListener { finishWith(RESULT_CANCELED) } }
        root.addView(close, FrameLayout.LayoutParams((48 * dp).toInt(), (48 * dp).toInt(), Gravity.TOP or Gravity.START))

        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            (shutter.layoutParams as FrameLayout.LayoutParams).bottomMargin = bars.bottom + (36 * dp).toInt()
            (close.layoutParams as FrameLayout.LayoutParams).apply {
                topMargin = bars.top + (8 * dp).toInt()
                leftMargin = (8 * dp).toInt()
            }
            shutter.requestLayout()
            close.requestLayout()
            insets
        }
        setContentView(root)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_PERMISSION)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSION) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startCamera() else finishWith(RESULT_DENIED)
    }

    private fun startCamera() {
        controller = LifecycleCameraController(this).apply {
            setEnabledUseCases(CameraController.IMAGE_CAPTURE)
            imageCaptureMode = ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY
            isTapToFocusEnabled = true
            isPinchToZoomEnabled = true
            bindToLifecycle(this@CaptureActivity)
        }
        preview.controller = controller
    }

    private fun take() {
        if (taking || !::controller.isInitialized) return
        taking = true
        shutter.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        // A quick blink of the preview, the shutter's only animation.
        ObjectAnimator.ofFloat(preview, View.ALPHA, 1f, 0.25f, 1f).setDuration(160).start()
        controller.takePicture(
            ImageCapture.OutputFileOptions.Builder(output).build(),
            ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(results: ImageCapture.OutputFileResults) = finishWith(RESULT_OK)

                override fun onError(e: ImageCaptureException) {
                    taking = false
                }
            },
        )
    }

    private fun finishWith(code: Int) {
        setResult(code)
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, android.R.anim.fade_out)
    }

    /** A white ring around a white disc that dips when pressed. */
    private class ShutterView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }

        init {
            isClickable = true
            contentDescription = "Take photo"
        }

        override fun setPressed(pressed: Boolean) {
            super.setPressed(pressed)
            animate().scaleX(if (pressed) 0.9f else 1f).scaleY(if (pressed) 0.9f else 1f).setDuration(80).start()
        }

        override fun onDraw(canvas: Canvas) {
            val r = width / 2f
            val stroke = r * 0.09f
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            canvas.drawCircle(r, r, r - stroke / 2, paint)
            paint.style = Paint.Style.FILL
            canvas.drawCircle(r, r, r * 0.78f, paint)
        }
    }

    /** A thin white ✕. */
    private class CloseView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = context.resources.displayMetrics.density * 2
            strokeCap = Paint.Cap.ROUND
        }

        init {
            isClickable = true
            contentDescription = "Close"
        }

        override fun onDraw(canvas: Canvas) {
            val a = width * 0.34f
            val b = width * 0.66f
            canvas.drawLine(a, a, b, b, paint)
            canvas.drawLine(b, a, a, b, paint)
        }
    }

    companion object {
        const val EXTRA_OUTPUT = "output"
        const val RESULT_DENIED = RESULT_FIRST_USER
        private const val REQUEST_PERMISSION = 1
    }
}
