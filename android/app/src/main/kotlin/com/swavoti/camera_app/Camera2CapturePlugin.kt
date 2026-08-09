package com.swavoti.camera_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Camera2CapturePlugin
 *
 * Opens Camera2 directly to take a single, ISP-maximised JPEG capture.
 * On MediaTek Helio G36 (Imagiq ISP) this triggers:
 *   - Hardware MFNR  (NOISE_REDUCTION_MODE_HIGH_QUALITY)
 *   - Hardware edge enhancement  (EDGE_MODE_HIGH_QUALITY)
 *   - Hardware HDR/Night if the OEM exposed it
 *   - Full-pipeline colour correction and tone mapping
 *
 * The Flutter camera plugin (CameraX) must have released the camera BEFORE
 * calling [captureHighQuality] — i.e. the controller must be disposed first.
 */
class Camera2CapturePlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.swavoti.camera/camera2")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getSupportedFeatures" -> {
                val cameraId = call.argument<String>("cameraId") ?: "0"
                getSupportedFeatures(cameraId, result)
            }
            "getVideoCapabilities" -> {
                val cameraId = call.argument<String>("cameraId") ?: "0"
                getVideoCapabilities(cameraId, result)
            }
            "captureHighQuality" -> {
                val cameraId = call.argument<String>("cameraId") ?: "0"
                captureHighQuality(cameraId, result)
            }
            "playShutterSound" -> {
                try {
                    android.media.MediaActionSound().play(android.media.MediaActionSound.SHUTTER_CLICK)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── Feature query ────────────────────────────────────────────────────────

    /**
     * Returns a map of which ISP quality features are supported on this device.
     * Flutter reads this once on init so it knows what to expect.
     */
    private fun getSupportedFeatures(cameraId: String, result: Result) {
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars = manager.getCameraCharacteristics(cameraId)

            val sceneModes  = chars.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: intArrayOf()
            val nrModes     = chars.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES) ?: intArrayOf()
            val edgeModes   = chars.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES) ?: intArrayOf()
            val hwLevel     = chars.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL) ?: CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY

            val features = mapOf(
                "hwLevel"               to hwLevel,
                "supportsHdr"           to sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR),
                "supportsNight"         to sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_NIGHT),
                "supportsHighQualityNR" to nrModes.contains(CameraMetadata.NOISE_REDUCTION_MODE_HIGH_QUALITY),
                "supportsHighQualityEdge" to edgeModes.contains(CameraMetadata.EDGE_MODE_HIGH_QUALITY),
                "availableSceneModes"   to sceneModes.toList(),
                "availableNRModes"      to nrModes.toList()
            )
            result.success(features)
        } catch (e: Exception) {
            result.error("QUERY_ERROR", e.message, null)
        }
    }

    /**
     * Returns hardware-supported video capabilities (max resolution, max FPS, resolution list).
     */
    private fun getVideoCapabilities(cameraId: String, result: Result) {
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars = manager.getCameraCharacteristics(cameraId)

            val streamMap = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val videoSizes = streamMap?.getOutputSizes(android.media.MediaRecorder::class.java)
                ?: streamMap?.getOutputSizes(android.graphics.SurfaceTexture::class.java)
                ?: arrayOf()

            var maxW = 0
            var maxH = 0
            var has4K = false
            var has1080p = false
            var has720p = false
            val supportedResolutions = mutableListOf<String>()

            for (size in videoSizes) {
                val w = size.width
                val h = size.height
                if (w * h > maxW * maxH) {
                    maxW = w
                    maxH = h
                }
                val minDim = Math.min(w, h)
                if (minDim >= 2160 && !has4K) {
                    has4K = true
                    supportedResolutions.add("4K")
                } else if (minDim >= 1080 && minDim < 2160 && !has1080p) {
                    has1080p = true
                    supportedResolutions.add("1080p")
                } else if (minDim >= 720 && minDim < 1080 && !has720p) {
                    has720p = true
                    supportedResolutions.add("720p")
                }
            }

            // Target FPS ranges
            val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: arrayOf()
            var maxFps = 30
            for (range in fpsRanges) {
                if (range.upper > maxFps) {
                    maxFps = range.upper
                }
            }

            val maxResLabel = when {
                has4K -> "4K"
                has1080p -> "1080p"
                has720p -> "720p"
                else -> "${Math.min(maxW, maxH)}p"
            }

            val caps = mapOf(
                "maxResolution" to maxResLabel,
                "maxFps" to maxFps,
                "has4K" to has4K,
                "has1080p" to has1080p,
                "has720p" to has720p,
                "supportedResolutions" to supportedResolutions,
                "maxW" to maxW,
                "maxH" to maxH
            )
            result.success(caps)
        } catch (e: Exception) {
            result.error("CAPS_ERROR", e.message, null)
        }
    }

    // ── High-quality ISP capture ─────────────────────────────────────────────

    /**
     * Opens Camera2, sets all available ISP quality parameters, captures one
     * JPEG and returns the raw bytes to Flutter.
     *
     * Parameter choices for MediaTek Helio G36 (Imagiq ISP):
     *   CONTROL_CAPTURE_INTENT_STILL_CAPTURE → tells ISP to engage MFNR pipeline
     *   NOISE_REDUCTION_MODE_HIGH_QUALITY    → hardware multi-frame NR
     *   EDGE_MODE_HIGH_QUALITY               → hardware sharpening
     *   COLOR_CORRECTION_ABERRATION_MODE_HIGH_QUALITY
     *   TONEMAP_MODE_HIGH_QUALITY
     *   CONTROL_SCENE_MODE_HDR or NIGHT if supported
     */
    private fun captureHighQuality(cameraId: String, result: Result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Camera permission not granted", null)
            return
        }

        val thread = HandlerThread("Camera2HighQuality").also { it.start() }
        val handler = Handler(thread.looper)

        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars   = manager.getCameraCharacteristics(cameraId)

            // ── Query available quality modes ────────────────────────────────
            val sceneModes  = chars.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: intArrayOf()
            val nrModes     = chars.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES) ?: intArrayOf()
            val edgeModes   = chars.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES) ?: intArrayOf()

            val hasHighQualityNR   = nrModes.contains(CameraMetadata.NOISE_REDUCTION_MODE_HIGH_QUALITY)
            val hasHighQualityEdge = edgeModes.contains(CameraMetadata.EDGE_MODE_HIGH_QUALITY)
            val hasHdr             = sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR)
            val hasNight           = sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_NIGHT)

            // ── Choose best capture size ─────────────────────────────────────
            val streamMap   = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
            val jpegSizes   = streamMap.getOutputSizes(ImageFormat.JPEG)
            // Use the largest available JPEG size for best quality
            val bestSize    = jpegSizes.maxByOrNull { it.width.toLong() * it.height.toLong() }!!

            val imageReader = ImageReader.newInstance(bestSize.width, bestSize.height, ImageFormat.JPEG, 2)

            // ── Open camera ──────────────────────────────────────────────────
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {

                override fun onOpened(device: CameraDevice) {
                    try {
                        val outputs = listOf(imageReader.surface)

                        device.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {

                            override fun onConfigured(session: CameraCaptureSession) {
                                try {
                                    val capture = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                                    capture.addTarget(imageReader.surface)

                                    // ── Core ISP quality parameters ──────────────────
                                    // Hardware & SoC Detection (MediaTek Imagiq, Qualcomm Spectre, Google Tensor)
                                    val socHardware  = (android.os.Build.HARDWARE ?: "").lowercase()
                                    val manufacturer = (android.os.Build.MANUFACTURER ?: "").lowercase()
                                    val isQualcomm   = socHardware.contains("qcom") || socHardware.contains("snapdragon")
                                    val isTensor     = socHardware.contains("gs101") || socHardware.contains("gs201") || socHardware.contains("zuma") || socHardware.contains("ripcurrent") || manufacturer.contains("google")

                                    capture.set(CaptureRequest.CONTROL_CAPTURE_INTENT,
                                        CameraMetadata.CONTROL_CAPTURE_INTENT_STILL_CAPTURE)

                                    capture.set(CaptureRequest.CONTROL_AF_MODE,
                                        CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE)

                                    capture.set(CaptureRequest.CONTROL_AWB_MODE,
                                        CameraMetadata.CONTROL_AWB_MODE_AUTO)

                                    // Hardware Zero-Shutter-Lag (ZSL) for Qualcomm & Google Tensor
                                    if (isQualcomm || isTensor) {
                                        try {
                                            capture.set(CaptureRequest.CONTROL_ENABLE_ZSL, true)
                                        } catch (_: Exception) {}
                                    }

                                    // Noise reduction — hardware MFNR
                                    if (hasHighQualityNR) {
                                        capture.set(CaptureRequest.NOISE_REDUCTION_MODE,
                                            CameraMetadata.NOISE_REDUCTION_MODE_HIGH_QUALITY)
                                    } else if (nrModes.contains(CameraMetadata.NOISE_REDUCTION_MODE_FAST)) {
                                        capture.set(CaptureRequest.NOISE_REDUCTION_MODE,
                                            CameraMetadata.NOISE_REDUCTION_MODE_FAST)
                                    }

                                    // Edge enhancement — hardware sharpening
                                    if (hasHighQualityEdge) {
                                        capture.set(CaptureRequest.EDGE_MODE,
                                            CameraMetadata.EDGE_MODE_HIGH_QUALITY)
                                    } else if (edgeModes.contains(CameraMetadata.EDGE_MODE_FAST)) {
                                        capture.set(CaptureRequest.EDGE_MODE, CameraMetadata.EDGE_MODE_FAST)
                                    }

                                    // Colour aberration correction
                                    capture.set(CaptureRequest.COLOR_CORRECTION_ABERRATION_MODE,
                                        CameraMetadata.COLOR_CORRECTION_ABERRATION_MODE_HIGH_QUALITY)

                                    // Tone mapping
                                    capture.set(CaptureRequest.TONEMAP_MODE,
                                        CameraMetadata.TONEMAP_MODE_HIGH_QUALITY)

                                    // Lens Shading & Hot Pixel (Qualcomm & Google Tensor ISP)
                                    try {
                                        capture.set(CaptureRequest.SHADING_MODE,
                                            CameraMetadata.SHADING_MODE_HIGH_QUALITY)
                                        capture.set(CaptureRequest.HOT_PIXEL_MODE,
                                            CameraMetadata.HOT_PIXEL_MODE_HIGH_QUALITY)
                                    } catch (_: Exception) {}

                                    // Distortion correction (Google Tensor & Snapdragon Spectre)
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                        try {
                                            capture.set(CaptureRequest.DISTORTION_CORRECTION_MODE,
                                                CameraMetadata.DISTORTION_CORRECTION_MODE_HIGH_QUALITY)
                                        } catch (_: Exception) {}
                                    }

                                    // Optical Image Stabilization (OIS)
                                    val oisModes = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION) ?: intArrayOf()
                                    if (oisModes.contains(CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON)) {
                                        try {
                                            capture.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                                                CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON)
                                        } catch (_: Exception) {}
                                    }

                                    // Scene mode — HDR > Night > none
                                    when {
                                        hasHdr -> {
                                            capture.set(CaptureRequest.CONTROL_MODE,
                                                CameraMetadata.CONTROL_MODE_USE_SCENE_MODE)
                                            capture.set(CaptureRequest.CONTROL_SCENE_MODE,
                                                CameraMetadata.CONTROL_SCENE_MODE_HDR)
                                        }
                                        hasNight -> {
                                            capture.set(CaptureRequest.CONTROL_MODE,
                                                CameraMetadata.CONTROL_MODE_USE_SCENE_MODE)
                                            capture.set(CaptureRequest.CONTROL_SCENE_MODE,
                                                CameraMetadata.CONTROL_SCENE_MODE_NIGHT)
                                        }
                                        else -> {
                                            capture.set(CaptureRequest.CONTROL_MODE,
                                                CameraMetadata.CONTROL_MODE_AUTO)
                                        }
                                    }

                                    // Maximum JPEG quality
                                    capture.set(CaptureRequest.JPEG_QUALITY, 97.toByte())

                                    // ── Image available listener ─────────────────────
                                    imageReader.setOnImageAvailableListener({ reader ->
                                        val image = reader.acquireLatestImage()
                                        try {
                                            val buffer = image?.planes?.get(0)?.buffer
                                            if (buffer != null) {
                                                val bytes = ByteArray(buffer.remaining())
                                                buffer.get(bytes)
                                                result.success(bytes)
                                            } else {
                                                result.error("NO_DATA", "Image buffer was null", null)
                                            }
                                        } finally {
                                            image?.close()
                                            session.close()
                                            device.close()
                                            imageReader.close()
                                            thread.quitSafely()
                                        }
                                    }, handler)

                                    session.capture(capture.build(), null, handler)

                                } catch (e: Exception) {
                                    result.error("CAPTURE_ERROR", e.message, null)
                                    cleanup(session, device, imageReader, thread)
                                }
                            }

                            override fun onConfigureFailed(session: CameraCaptureSession) {
                                result.error("CONFIG_FAILED", "CaptureSession configuration failed", null)
                                device.close()
                                imageReader.close()
                                thread.quitSafely()
                            }
                        }, handler)
                    } catch (e: Exception) {
                        result.error("SESSION_ERROR", e.message, null)
                        device.close()
                        thread.quitSafely()
                    }
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    thread.quitSafely()
                }

                override fun onError(device: CameraDevice, error: Int) {
                    result.error("CAMERA_ERROR", "Camera device error: $error", null)
                    device.close()
                    thread.quitSafely()
                }
            }, handler)

        } catch (e: Exception) {
            result.error("OPEN_ERROR", e.message, null)
            thread.quitSafely()
        }
    }

    private fun cleanup(
        session: CameraCaptureSession,
        device: CameraDevice,
        imageReader: ImageReader,
        thread: HandlerThread
    ) {
        session.close()
        device.close()
        imageReader.close()
        thread.quitSafely()
    }
}
