package com.oscargalvin.vidgame

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.CompositionSettings
import androidx.camera.core.ConcurrentCamera
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat

/**
 * VidGame camera: your face (front camera) in a small window over the
 * background (back camera), both live and recorded into one video.
 */
class MainActivity : ComponentActivity() {
    private lateinit var previewView: PreviewView
    private lateinit var status: TextView
    private lateinit var recordBtn: Button
    private lateinit var pauseBtn: Button
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var paused = false

    private val askPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
            if (result[Manifest.permission.CAMERA] == true) startCameras()
            else status.text = "VidGame needs the camera. Allow it in Settings → Apps → VidGame → Permissions."
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(Color.BLACK)
        previewView = PreviewView(this).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE }

        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(32, 48, 32, 16)
            gravity = Gravity.CENTER
            setBackgroundColor(0x88000000.toInt())
            text = "Starting cameras…"
        }

        recordBtn = Button(this).apply {
            text = "● Record"
            setTextColor(Color.WHITE)
            textSize = 18f
            background = GradientDrawable().apply { cornerRadius = 100f; setColor(0xFFE11D48.toInt()) }
            setOnClickListener { toggleRecording() }
        }
        pauseBtn = Button(this).apply {
            text = "❚❚ Pause"
            setTextColor(Color.WHITE)
            textSize = 16f
            background = GradientDrawable().apply { cornerRadius = 100f; setColor(0xFF333333.toInt()) }
            isEnabled = false
            alpha = 0.5f
            setOnClickListener { togglePause() }
        }
        val siteBtn = Button(this).apply {
            text = "Open VidGame"
            setTextColor(Color.WHITE)
            textSize = 14f
            background = GradientDrawable().apply { cornerRadius = 100f; setColor(0xFF333333.toInt()) }
            setOnClickListener {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://oscargalvin.github.io/OSCAR-Games/")))
            }
        }

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(24, 24, 24, 64)
            val lp = { LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { setMargins(16, 0, 16, 0) } }
            addView(pauseBtn, lp())
            addView(recordBtn, lp())
            addView(siteBtn, lp())
        }

        val root = FrameLayout(this)
        root.addView(previewView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        root.addView(status, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.TOP))
        root.addView(bar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))
        setContentView(root)

        askPermissions.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
    }

    private fun startCameras() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                bindCameras(future.get())
            } catch (e: Exception) {
                status.text = "The cameras couldn't start: ${e.message}"
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bindCameras(provider: ProcessCameraProvider) {
        // Find a front + back camera pair that this phone can run at the same time.
        var front: CameraSelector? = null
        var back: CameraSelector? = null
        for (combo in provider.availableConcurrentCameraInfos) {
            val f = combo.firstOrNull { it.lensFacing == CameraSelector.LENS_FACING_FRONT }
            val b = combo.firstOrNull { it.lensFacing == CameraSelector.LENS_FACING_BACK }
            if (f != null && b != null) {
                front = f.cameraSelector
                back = b.cameraSelector
                break
            }
        }

        val preview = Preview.Builder().build()
        preview.setSurfaceProvider(previewView.surfaceProvider)
        val recorder = Recorder.Builder()
            .setQualitySelector(QualitySelector.from(Quality.HD, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)))
            .build()
        val capture = VideoCapture.withOutput(recorder)
        videoCapture = capture

        provider.unbindAll()
        if (front != null && back != null) {
            val group = UseCaseGroup.Builder().addUseCase(preview).addUseCase(capture).build()
            // Background: back camera fills the screen.
            val background = ConcurrentCamera.SingleCameraConfig(
                back, group,
                CompositionSettings.Builder().setAlpha(1f).setOffset(0f, 0f).setScale(1f, 1f).build(),
                this,
            )
            // Your face: front camera in a small window in the corner.
            val face = ConcurrentCamera.SingleCameraConfig(
                front, group,
                CompositionSettings.Builder().setAlpha(1f).setOffset(0.55f, -0.6f).setScale(0.38f, 0.38f).build(),
                this,
            )
            try {
                provider.bindToLifecycle(listOf(background, face))
                status.text = "😀 Your face + background. Press ● Record."
                return
            } catch (e: Exception) {
                provider.unbindAll()
                status.text = "Sorry, this phone couldn't record both cameras together (${e.message}). Only the back camera is on."
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
                return
            }
        } else {
            provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
            status.text = "Sorry, this phone can't use the front and back cameras at the same time, so only the back camera is on."
        }
    }

    @SuppressLint("MissingPermission")
    private fun toggleRecording() {
        val capture = videoCapture ?: return
        val current = recording
        if (current != null) {
            current.stop()
            recording = null
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "VidGame-${System.currentTimeMillis()}")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/VidGame")
        }
        val output = MediaStoreOutputOptions.Builder(contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            .setContentValues(values)
            .build()
        var pending = capture.output.prepareRecording(this, output)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            pending = pending.withAudioEnabled()
        }
        recording = pending.start(ContextCompat.getMainExecutor(this)) { event ->
            when (event) {
                is VideoRecordEvent.Start -> {
                    recordBtn.text = "■ Stop"
                    pauseBtn.isEnabled = true; pauseBtn.alpha = 1f
                    paused = false
                }
                is VideoRecordEvent.Finalize -> {
                    recordBtn.text = "● Record"
                    pauseBtn.text = "❚❚ Pause"
                    pauseBtn.isEnabled = false; pauseBtn.alpha = 0.5f
                    if (event.hasError()) {
                        Toast.makeText(this, "Recording failed (error ${event.error})", Toast.LENGTH_LONG).show()
                    } else {
                        status.text = "Saved to your gallery (Movies/VidGame). Post it on VidGame with ＋ Post → Upload."
                        Toast.makeText(this, "Video saved to your gallery!", Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    private fun togglePause() {
        val r = recording ?: return
        if (paused) { r.resume(); pauseBtn.text = "❚❚ Pause" } else { r.pause(); pauseBtn.text = "▶ Resume" }
        paused = !paused
    }
}
