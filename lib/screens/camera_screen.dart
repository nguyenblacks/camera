import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gal/gal.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:color_filter_extension/color_filter_extension.dart';

import '../models/camera_settings.dart';
import '../services/device_info_service.dart';
import '../services/enhancement_service.dart';
import '../services/face_detection_service.dart';
import '../services/native_capture_service.dart';
import '../services/night_service.dart';
import '../services/portrait_service.dart';
import '../services/sound_service.dart';
import '../services/timelapse_service.dart';
import '../services/voice_capture_service.dart';
import '../services/scanner_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/shutter_button.dart';
import '../widgets/thumbnail_widget.dart';
import '../widgets/top_menu_widget.dart';
import '../widgets/zoom_control_widget.dart';
import 'settings_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  CameraSettings _settings = CameraSettings();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _permissionDenied = false;

  // Video recording state
  bool _isRecordingVideo = false;
  int _videoRecordSeconds = 0;
  Timer? _videoRecordTimer;

  // Night Sight state
  bool _isCapturingNight = false;
  int _nightFrameCount = 0;

  // Timelapse state
  final TimelapseService _timelapseService = TimelapseService();
  TimelapseState _timelapseState = const TimelapseState(
    isRecording: false,
    capturedFrames: 0,
    elapsedSeconds: 0,
  );

  // Thumbnail state
  Uint8List? _thumbnailBytes;
  ThumbnailState _thumbnailState = ThumbnailState.idle;
  String? _lastSavedFilePath;

  // Countdown timer
  int _countdownValue = 0;
  Timer? _countdownTimer;

  // Voice shutter
  final VoiceCaptureService _voiceService = VoiceCaptureService();
  bool _voiceListening = false;

  // Device info
  String _deviceModel = '';

  // ── Zoom state ──────────────────────────────────────────────────────────
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  bool _hasUltraWide = false;

  // Hardware video capabilities state
  String _videoCapsText = '';
  HardwareVideoCaps? _activeVideoCaps;

  // ── Stream Services ────────────────────────────────────────────────
  final FaceDetectionService _faceService = FaceDetectionService();
  final ScannerService _scannerService = ScannerService();
  bool _isImageStreamActive = false;
  bool _isBokehExpanded = false;

  // UI state for right-edge panels
  bool _showFilterCarousel = false;
  bool _showTimelapseSettings = false;

  static List<double>? _presetToMatrix(ColorFiltersPreset? preset) {
    if (preset == null || preset.filters.isEmpty) return null;
    return ColorFilterExt.merged(preset.filters).matrix;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
    _voiceService.initialize();
    _loadDeviceModel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _videoRecordTimer?.cancel();
    _voiceService.dispose();
    _faceService.dispose();
    _scannerService.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _voiceService.stopListening();
      if (_timelapseState.isRecording) {
        _timelapseService.stop(onUpdate: (s) => setState(() => _timelapseState = s));
      }
      _stopImageStream();
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> _loadDeviceModel() async {
    final model = await DeviceInfoService.getDeviceModel();
    if (mounted) setState(() => _deviceModel = model);
  }

  Future<void> _initCamera() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() => _permissionDenied = true);
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // Check for ultrawide lens (typically index 2 or lens with wider FOV)
      _hasUltraWide = _cameras.where((c) =>
          c.lensDirection == CameraLensDirection.back).length > 1;

      final isp = await NativeCaptureService.getSupportedFeatures();
      debugPrint('Device ISP features: $isp');

      await _setupController(
        _settings.isFrontCamera
            ? _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.front,
                orElse: () => _cameras.first)
            : _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
                orElse: () => _cameras.first),
      );
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    if (mounted) {
      setState(() => _isInitialized = false);
    }

    // Stop image stream before disposing
    await _stopImageStream();

    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // Query real hardware capabilities for active camera
    final cameraId = (camera.lensDirection == CameraLensDirection.front) ? '1' : '0';
    final videoCaps = await NativeCaptureService.getVideoCapabilities(cameraId: cameraId);

    // Determine ResolutionPreset based on selected VideoQuality & hardware caps
    ResolutionPreset preset = ResolutionPreset.high;
    if (_settings.cameraMode == CameraMode.video || _settings.cameraMode == CameraMode.timelapse) {
      switch (_settings.videoQuality) {
        case VideoQuality.uhd:
          preset = videoCaps.has4K ? ResolutionPreset.ultraHigh : ResolutionPreset.veryHigh;
          break;
        case VideoQuality.fhd:
          preset = videoCaps.has1080p ? ResolutionPreset.veryHigh : ResolutionPreset.high;
          break;
        case VideoQuality.hd:
          preset = ResolutionPreset.high;
          break;
      }
    } else {
      preset = _settings.quality == PictureQuality.low ? ResolutionPreset.veryHigh : ResolutionPreset.max;
    }

    final newController = CameraController(
      camera,
      preset,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await newController.initialize();

      try {
        await newController.setFlashMode(_settings.flashMode);
      } catch (_) {
        try {
          await newController.setFlashMode(FlashMode.off);
        } catch (_) {}
      }

      // Query zoom range
      final minZ = await newController.getMinZoomLevel();
      final maxZ = await newController.getMaxZoomLevel();

      // Format plain text video specs
      final previewSize = newController.value.previewSize;
      final activeRes = (previewSize != null)
          ? '${previewSize.height.toInt()}p'
          : videoCaps.maxResolution;
      final capsText = '$activeRes @ ${videoCaps.maxFps}fps';

      if (mounted) {
        setState(() {
          _controller = newController;
          _isInitialized = true;
          _minZoom = minZ;
          _maxZoom = maxZ;
          _currentZoom = 1.0;
          _activeVideoCaps = videoCaps;
          _videoCapsText = capsText;
        });
      }

      // Start image stream for face detection and QR scanning
      if (_settings.cameraMode != CameraMode.video) {
        _startImageStream();
      }
    } catch (e) {
      debugPrint('Controller setup error: $e');
      if (mounted) {
        setState(() => _isInitialized = false);
      }
      try {
        await newController.dispose();
      } catch (_) {}
    }
  }

  // ── Zoom ────────────────────────────────────────────────────────────────

  Future<void> _setZoom(double zoom) async {
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setZoomLevel(clamped);
      if (mounted) setState(() => _currentZoom = clamped);
    } catch (e) {
      debugPrint('Zoom error: $e');
    }
  }

  // ── Image Streaming (Face & QR) ─────────────────────────────────────────

  void _startImageStream() {
    if (_isImageStreamActive || _controller == null) return;
    _faceService.initialize();
    _scannerService.resume();
    _isImageStreamActive = true;

    final camera = _settings.isFrontCamera
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first)
        : _cameras.first;

    try {
      _controller!.startImageStream((CameraImage image) {
        if (_settings.isFrontCamera || _settings.cameraMode == CameraMode.portrait) {
          _faceService.processImage(image, camera);
        }
        _scannerService.processImage(image, camera);
      });
    } catch (e) {
      debugPrint('Image stream start error: $e');
      _isImageStreamActive = false;
    }
  }

  Future<void> _stopImageStream() async {
    if (!_isImageStreamActive) return;
    _isImageStreamActive = false;
    _faceService.stop();
    _scannerService.stop();
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}
  }

  // ── Shutter action entry point ────────────────────────────────────────────

  Future<void> _onShutterPressed() async {
    if (_isProcessing || _controller == null) return;

    switch (_settings.cameraMode) {
      case CameraMode.photo:
        if (_settings.timerSeconds > 0 && _settings.captureMethod == CaptureMethod.normal) {
          _startTimerCountdown(_startCapture);
        } else {
          _startCapture();
        }
        break;
      case CameraMode.portrait:
        if (_settings.timerSeconds > 0 && _settings.captureMethod == CaptureMethod.normal) {
          _startTimerCountdown(_startPortraitCapture);
        } else {
          _startPortraitCapture();
        }
        break;
      case CameraMode.video:
        _toggleVideoRecording();
        break;
      case CameraMode.night:
        _startNightCapture();
        break;
      case CameraMode.timelapse:
        _toggleTimelapse();
        break;
    }
  }

  void _startTimerCountdown(VoidCallback onComplete) {
    setState(() => _countdownValue = _settings.timerSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _countdownValue--);
      if (_countdownValue <= 0) {
        t.cancel();
        onComplete();
      }
    });
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (_controller == null || _isProcessing) return;

    // Stop stream before taking picture (can't take picture while streaming)
    final wasStreaming = _isImageStreamActive;
    if (_isImageStreamActive) {
      await _stopImageStream();
    }

    setState(() {
      _isProcessing = true;
      _thumbnailState = ThumbnailState.idle;
    });

    if (_settings.enableShutterSound) SoundService.playShutterSound();
    HapticFeedback.heavyImpact();

    try {
      Uint8List raw1;
      Uint8List? raw2;

      final useNative = !_settings.isFrontCamera &&
          _settings.quality != PictureQuality.low;

      if (useNative) {
        // ── Camera2 path: full sensor resolution (true 8MP) ──────────────────
        // Dispose Flutter controller so Camera2 can open the camera
        final cam = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
        await _controller!.dispose();
        _controller = null;

        final cameraId = '0';
        final bytes = await NativeCaptureService.captureHighQuality(cameraId: cameraId);

        // Reinitialise preview immediately
        await _setupController(cam);

        if (bytes == null || bytes.isEmpty) {
          // Camera2 failed — fall back to Flutter takePicture
          final XFile fallback = await _controller!.takePicture();
          raw1 = await fallback.readAsBytes();
          try { File(fallback.path).deleteSync(); } catch (_) {}
        } else {
          raw1 = bytes;
        }

        // Two-frame blend: capture a second shot via Camera2 if quality needs it
        if (_settings.usesTwoFrames && _controller != null) {
          await Future.delayed(const Duration(milliseconds: 180));
          await _controller!.dispose();
          _controller = null;
          final bytes2 = await NativeCaptureService.captureHighQuality(cameraId: cameraId);
          await _setupController(cam);
          if (bytes2 != null && bytes2.isNotEmpty) raw2 = bytes2;
        }
      } else {
        // ── Flutter CameraX path: front camera or low quality ─────────────────
        final XFile f1 = await _controller!.takePicture();
        raw1 = await f1.readAsBytes();
        try { File(f1.path).deleteSync(); } catch (_) {}

        if (_settings.usesTwoFrames) {
          await Future.delayed(const Duration(milliseconds: 180));
          final XFile f2 = await _controller!.takePicture();
          raw2 = await f2.readAsBytes();
          try { File(f2.path).deleteSync(); } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _thumbnailBytes = raw1;
          _thumbnailState = ThumbnailState.processing;
        });
      }

      final finalJpeg = await EnhancementService.enhanceWithQuality(
        frame1: raw1,
        frame2: raw2,
        quality: _settings.quality,
        deviceModel: _settings.watermarkEnabled ? _deviceModel : null,
        filterMatrix: _presetToMatrix(_settings.activeFilter),
      );

      if (finalJpeg != null) {
        await _saveToGallery(finalJpeg);
      }

      _finishProcessing(finalJpeg);
    } catch (e) {
      debugPrint('Capture error: $e');
      _finishProcessing(null);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      // Resume stream if we were streaming
      if (wasStreaming && mounted && _settings.cameraMode != CameraMode.video) {
        Future.delayed(const Duration(milliseconds: 300), _startImageStream);
      }
    }
  }

  // ── Portrait mode (ML Kit segmentation + bokeh) ─────────────────────────

  Future<void> _startPortraitCapture() async {
    if (_controller == null || _isProcessing) return;

    final wasStreaming = _isImageStreamActive;
    if (wasStreaming) await _stopImageStream();

    setState(() {
      _isProcessing = true;
      _thumbnailState = ThumbnailState.idle;
    });

    if (_settings.enableShutterSound) SoundService.playShutterSound();
    HapticFeedback.heavyImpact();

    try {
      final XFile f1 = await _controller!.takePicture();
      final Uint8List raw1 = await f1.readAsBytes();
      try { File(f1.path).deleteSync(); } catch (_) {}

      if (mounted) {
        setState(() {
          _thumbnailBytes = raw1;
          _thumbnailState = ThumbnailState.processing;
        });
      }

      // Apply ML Kit selfie segmentation + Gaussian bokeh
      final portrayed = await PortraitService.applyPortraitBokeh(
        imageBytes: raw1,
        blurLevel: _settings.bokehBlurLevel,
        isFrontCamera: _settings.isFrontCamera,
      );

      // Save bokeh-rendered image to gallery
      await _saveToGallery(portrayed);

      _finishProcessing(portrayed);
    } catch (e) {
      debugPrint('Portrait capture error: $e');
      _finishProcessing(null);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      if (wasStreaming && mounted) {
        Future.delayed(const Duration(milliseconds: 300), _startImageStream);
      }
    }
  }

  // ── Night Sight capture (4-frame multi-shot low-light) ────────────────────

  Future<void> _startNightCapture() async {
    if (_controller == null || _isProcessing) return;

    final wasStreaming = _isImageStreamActive;
    if (wasStreaming) await _stopImageStream();

    setState(() {
      _isProcessing = true;
      _isCapturingNight = true;
      _nightFrameCount = 0;
      _thumbnailState = ThumbnailState.idle;
    });

    if (_settings.enableShutterSound) SoundService.playShutterSound();
    HapticFeedback.mediumImpact();

    final List<Uint8List> frames = [];

    try {
      // Fire 4 rapid low-noise hardware ISP shots
      for (int i = 1; i <= 4; i++) {
        if (!mounted) break;
        setState(() => _nightFrameCount = i);

        final XFile f = await _controller!.takePicture();
        final Uint8List bytes = await f.readAsBytes();
        frames.add(bytes);
        try { File(f.path).deleteSync(); } catch (_) {}

        if (i == 1 && mounted) {
          setState(() {
            _thumbnailBytes = bytes;
            _thumbnailState = ThumbnailState.processing;
          });
        }
        if (i < 4) await Future.delayed(const Duration(milliseconds: 160));
      }

      // Process in NightSight isolate: 4-frame noise reduction + shadow lift
      final finalJpeg = await NightService.processNightSight(
        frames: frames,
        deviceModel: _settings.watermarkEnabled ? _deviceModel : null,
      );

      if (finalJpeg != null) {
        await _saveToGallery(finalJpeg);
      }

      _finishProcessing(finalJpeg);
    } catch (e) {
      debugPrint('Night capture error: $e');
      _finishProcessing(null);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isCapturingNight = false;
        });
      }
      if (wasStreaming && mounted) {
        Future.delayed(const Duration(milliseconds: 300), _startImageStream);
      }
    }
  }

  // ── Timelapse mode recording ──────────────────────────────────────────────

  void _toggleTimelapse() {
    if (_timelapseState.isRecording) {
      _timelapseService.stop(onUpdate: (s) {
        if (mounted) setState(() => _timelapseState = s);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Timelapse saved (${_timelapseState.capturedFrames} frames)'),
          backgroundColor: const Color(0xFF222222),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } else {
      _timelapseService.start(
        intervalSeconds: _settings.timelapseIntervalSeconds,
        onFrameTrigger: () async {
          if (_controller == null || !_controller!.value.isInitialized) return;
          try {
            final XFile f = await _controller!.takePicture();
            final Uint8List bytes = await f.readAsBytes();
            try { File(f.path).deleteSync(); } catch (_) {}

            if (mounted) {
              setState(() {
                _thumbnailBytes = bytes;
                _thumbnailState = ThumbnailState.processing;
              });
            }

            final enhanced = await EnhancementService.enhanceWithQuality(
              frame1: bytes,
              quality: PictureQuality.low,
              deviceModel: _settings.watermarkEnabled ? _deviceModel : null,
              filterMatrix: _presetToMatrix(_settings.activeFilter),
            );

            if (enhanced != null) {
              await _saveToGallery(enhanced);
              if (mounted) setState(() => _thumbnailState = ThumbnailState.done);
            }
          } catch (e) {
            debugPrint('Timelapse frame error: $e');
          }
        },
        onUpdate: (s) {
          if (mounted) setState(() => _timelapseState = s);
        },
      );
    }
  }

  Future<void> _saveToGallery(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/swavoti_$ts.jpg';
      await File(path).writeAsBytes(bytes);
      _lastSavedFilePath = path;
      await Gal.putImage(path, album: 'Swavoti Camera');
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  void _finishProcessing(Uint8List? enhanced) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = false;
      _thumbnailBytes = enhanced ?? _thumbnailBytes;
      _thumbnailState = ThumbnailState.done;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _thumbnailState = ThumbnailState.idle);
    });

    if (_settings.captureMethod == CaptureMethod.voice && !_voiceListening) {
      Future.delayed(const Duration(milliseconds: 600), _startVoiceListening);
    }
  }

  // ── Voice shutter ─────────────────────────────────────────────────────────

  Future<void> _startVoiceListening() async {
    if (_voiceListening || _isProcessing) return;
    setState(() => _voiceListening = true);
    await _voiceService.startListening(onTriggered: () {
      if (mounted) setState(() => _voiceListening = false);
      _startCapture();
    });
  }

  Future<void> _stopVoiceListening() async {
    setState(() => _voiceListening = false);
    await _voiceService.stopListening();
  }

  Future<void> _setCaptureMethod(CaptureMethod method) async {
    if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();

    final newSettings = _settings.copyWith(captureMethod: method);
    setState(() => _settings = newSettings);

    if (method == CaptureMethod.voice) {
      await _startVoiceListening();
    }
  }

  // ── Video recording ───────────────────────────────────────────────────────

  Future<void> _toggleVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecordingVideo) {
      try {
        final XFile videoFile = await _controller!.stopVideoRecording();
        _videoRecordTimer?.cancel();
        setState(() { _isRecordingVideo = false; _videoRecordSeconds = 0; });
        await Gal.putVideo(videoFile.path, album: 'Swavoti Camera');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Video saved to Gallery'),
            backgroundColor: Color(0xFF222222),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ));
        }
      } catch (e) {
        debugPrint('Stop video error: $e');
        setState(() { _isRecordingVideo = false; _videoRecordSeconds = 0; });
      }
    } else {
      // Stop stream before recording
      if (_isImageStreamActive) {
        await _stopImageStream();
      }
      try {
        await _controller!.startVideoRecording();
        HapticFeedback.mediumImpact();
        if (_settings.enableShutterSound) SoundService.playShutterSound();
        setState(() { _isRecordingVideo = true; _videoRecordSeconds = 0; });
        _videoRecordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          setState(() => _videoRecordSeconds++);
        });
      } catch (e) {
        debugPrint('Start video error: $e');
      }
    }
  }

  // ── Settings & flip ────────────────────────────────────────────────────────

  Future<void> _flipCamera() async {
    if (_isProcessing || _isRecordingVideo || _cameras.length < 2) return;

    if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();

    final newSettings = _settings.copyWith(isFrontCamera: !_settings.isFrontCamera);

    final target = newSettings.isFrontCamera
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first)
        : _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first);

    setState(() {
      _settings = newSettings;
      _currentZoom = 1.0;
    });
    await _setupController(target);
  }

  Future<void> _toggleVideoQuality() async {
    if (_isProcessing || _isRecordingVideo || _cameras.isEmpty) return;

    final caps = _activeVideoCaps;
    VideoQuality nextQuality;
    if (_settings.videoQuality == VideoQuality.hd) {
      nextQuality = (caps != null && caps.has1080p) ? VideoQuality.fhd : VideoQuality.hd;
    } else if (_settings.videoQuality == VideoQuality.fhd) {
      nextQuality = (caps != null && caps.has4K) ? VideoQuality.uhd : VideoQuality.hd;
    } else {
      nextQuality = VideoQuality.hd;
    }

    final newSettings = _settings.copyWith(videoQuality: nextQuality);
    _onSettingsChanged(newSettings);
  }

  void _onSettingsChanged(CameraSettings newSettings) async {
    final videoQualityChanged = newSettings.videoQuality != _settings.videoQuality;
    final modeChanged = newSettings.cameraMode != _settings.cameraMode;

    // Handle location permission request when enabling location info
    if (newSettings.saveLocationInfo && !_settings.saveLocationInfo) {
      final locPerm = await Permission.location.request();
      if (!locPerm.isGranted) {
        // Don't enable if permission denied
        return;
      }
    }

    setState(() => _settings = newSettings);
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFlashMode(newSettings.flashMode);
      } catch (e) {
        debugPrint('Flash mode change error: $e');
      }
    }

    if (videoQualityChanged || (modeChanged && newSettings.cameraMode == CameraMode.video)) {
      if (_cameras.isNotEmpty) {
        final target = _settings.isFrontCamera
            ? _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.front,
                orElse: () => _cameras.first)
            : _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
                orElse: () => _cameras.first);
        await _setupController(target);
      }
    }
  }

  void _openSettingsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings,
          onSettingsChanged: _onSettingsChanged,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) return _buildPermissionDenied();
    if (!_isInitialized || _controller == null) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          _buildPreviewWithAspectRatio(),
          if (_settings.showGrid) _buildGrid(),
          if (_isRecordingVideo) _buildVideoTimer(),
          if (_timelapseState.isRecording) _buildTimelapseTimer(),
          if (_isCapturingNight) _buildNightSightOverlay(),
          if (_countdownValue > 0) _buildCountdown(),
          if (_voiceListening) _buildVoiceOverlay(),

          // Face detection overlay
          if (_settings.isFrontCamera || _settings.cameraMode == CameraMode.portrait) _buildFaceOverlay(),

          // QR code detection overlay
          _buildQrOverlay(),

          SafeArea(child: _buildControls()),
        ],
      ),
    );
  }

  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _buildPreviewWithAspectRatio() {
    final double? targetRatio = _settings.aspectRatioRatio;

    Widget previewWidget = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.previewSize!.height,
        height: _controller!.value.previewSize!.width,
        child: Builder(builder: (context) {
          final matrix = _presetToMatrix(_settings.activeFilter);
          if (matrix != null) {
            return ColorFiltered(
              colorFilter: ColorFilter.matrix(matrix),
              child: CameraPreview(_controller!),
            );
          }
          return CameraPreview(_controller!);
        }),
      ),
    );

    if (targetRatio != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: targetRatio,
          child: ClipRect(child: previewWidget),
        ),
      );
    }
    return SizedBox.expand(child: previewWidget);
  }

  Widget _buildQrOverlay() {
    return ValueListenableBuilder<String?>(
      valueListenable: _scannerService.detectedUrl,
      builder: (context, url, _) {
        if (url == null) return const SizedBox.shrink();

        // Show a floating pill in the center-ish of the screen
        return Positioned(
          bottom: MediaQuery.of(context).size.height * 0.4,
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open link')),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(200),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.amber.withAlpha(150), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Visit: $url',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ).animate().slideY(begin: 0.5, end: 0, curve: Curves.easeOutBack, duration: 300.ms).fadeIn(),
          ),
        );
      },
    );
  }

  /// Draws yellow outlined rectangles on detected faces.
  Widget _buildFaceOverlay() {
    return ValueListenableBuilder<List<DetectedFace>>(
      valueListenable: _faceService.faces,
      builder: (context, faces, _) {
        if (faces.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: faces.map((face) {
                // Mirror the x-axis for front camera only
                final rect = face.normalizedRect;
                final left = _settings.isFrontCamera
                    ? (1.0 - rect.right) * constraints.maxWidth
                    : rect.left * constraints.maxWidth;
                final top = rect.top * constraints.maxHeight;
                final width = rect.width * constraints.maxWidth;
                final height = rect.height * constraints.maxHeight;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.amber.withAlpha(200),
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoTimer() {
    final mins = (_videoRecordSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_videoRecordSeconds % 60).toString().padLeft(2, '0');
    return Positioned(
      top: 60,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(200),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(duration: 500.ms),
            const SizedBox(width: 8),
            Text('$mins:$secs',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelapseTimer() {
    final mins = (_timelapseState.elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_timelapseState.elapsedSeconds % 60).toString().padLeft(2, '0');
    return Positioned(
      top: 60,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.withAlpha(220),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timelapse_rounded, color: Colors.black, size: 16)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .rotate(duration: 2000.ms),
            const SizedBox(width: 8),
            Text(
              'TIMELAPSE  $mins:$secs  •  ${_timelapseState.capturedFrames} frames',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNightSightOverlay() {
    return Positioned(
      bottom: 150,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber.withAlpha(180)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nightlight_round, color: Colors.amber, size: 18)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.4, end: 1.0, duration: 600.ms),
            const SizedBox(width: 10),
            Text(
              'Night Sight ($_nightFrameCount/4) • Hold steady...',
              style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter(), child: const SizedBox.expand()),
    );
  }

  Widget _buildCountdown() {
    return Center(
      child: Text(
        '$_countdownValue',
        style: const TextStyle(
          color: Colors.white, fontSize: 120, fontWeight: FontWeight.w200,
          shadows: [Shadow(color: Colors.black54, blurRadius: 20)],
        ),
      ).animate(key: ValueKey(_countdownValue)).scale(
            begin: const Offset(1.3, 1.3), end: const Offset(1.0, 1.0),
            duration: 400.ms, curve: Curves.easeOut),
    );
  }

  Widget _buildVoiceOverlay() {
    return Positioned(
      top: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(170),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_rounded, color: Colors.red, size: 18)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 1.0, end: 0.3, duration: 600.ms),
            const SizedBox(width: 10),
            const Text(
              'Say  "Cheese"',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        TopMenuWidget(
          settings: _settings,
          onSettingsChanged: _onSettingsChanged,
          onOpenSettings: _openSettingsScreen,
          videoCapsText: _videoCapsText,
          onToggleVideoQuality: _toggleVideoQuality,
        ),
        const Spacer(),

        // Zoom control, Filters, or Timelapse settings (rear camera only)
        if (!_settings.isFrontCamera)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Keep the height structured by using an invisible placeholder if needed,
                // but the child widgets themselves have height.
                Container(
                  width: double.infinity,
                  height: 50, // ensures the stack has at least 50px height
                  alignment: Alignment.bottomCenter,
                  child: () {
                    if (_showFilterCarousel) return _buildFilterCarousel();
                    if (_showTimelapseSettings) return _buildTimelapseSettingsUI();
                    if (_maxZoom > 1.0) {
                      return ZoomControlWidget(
                        currentZoom: _currentZoom,
                        minZoom: _minZoom,
                        maxZoom: _maxZoom,
                        hasUltraWide: _hasUltraWide,
                        onZoomChanged: _setZoom,
                      );
                    }
                    return const SizedBox.shrink();
                  }(),
                ),
                Positioned(
                  right: 16,
                  bottom: 5,
                  child: _buildRightEdgeToggle(),
                ),
              ],
            ),
          ),

        _buildModeSelector(),
        const SizedBox(height: 10),
        _buildCaptureMethodRow(),
        if (_settings.cameraMode == CameraMode.portrait)
          _buildBokehPill(),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildFlipButton(),
              ShutterButton(
                onPressed: _isProcessing ? null : _onShutterPressed,
                isProcessing: _isProcessing,
                isVideoMode: _settings.cameraMode == CameraMode.video || _settings.cameraMode == CameraMode.timelapse,
                isRecording: _isRecordingVideo || _timelapseState.isRecording,
              ),
              _buildThumbnail(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    return GestureDetector(
      onTap: _lastSavedFilePath != null
          ? () => OpenFile.open(_lastSavedFilePath!)
          : null,
      child: ThumbnailWidget(
        imageBytes: _thumbnailBytes,
        state: _thumbnailState,
        onTap: null,
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      (CameraMode.photo, 'PHOTO'),
      (CameraMode.video, 'VIDEO'),
      (CameraMode.night, 'NIGHT'),
      (CameraMode.timelapse, 'TIMELAPSE'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: modes.map((entry) {
          final mode = entry.$1;
          final label = entry.$2;
          final isSelected = _settings.cameraMode == mode;
          return GestureDetector(
            onTap: _isProcessing || _isRecordingVideo || _timelapseState.isRecording
                ? null
                : () async {
                    if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();
                    _onSettingsChanged(_settings.copyWith(cameraMode: mode));
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white38,
                      fontSize: isSelected ? 12 : 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 1.1,
                    ),
                    child: Text(label),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 20 : 0,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (mode == CameraMode.portrait ? const Color(0xFFFF6B9D) : Colors.amber)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: (mode == CameraMode.portrait
                                        ? const Color(0xFFFF6B9D)
                                        : Colors.amber)
                                    .withAlpha(180),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRightEdgeToggle() {
    if (_settings.cameraMode == CameraMode.photo) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _showFilterCarousel = !_showFilterCarousel;
            _showTimelapseSettings = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            shape: BoxShape.circle,
            border: Border.all(color: _showFilterCarousel ? Colors.amber : Colors.white30),
          ),
          child: Icon(Icons.edit, color: _showFilterCarousel ? Colors.amber : Colors.white, size: 20),
        ),
      );
    } else if (_settings.cameraMode == CameraMode.timelapse) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _showTimelapseSettings = !_showTimelapseSettings;
            _showFilterCarousel = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            shape: BoxShape.circle,
            border: Border.all(color: _showTimelapseSettings ? Colors.amber : Colors.white30),
          ),
          child: Icon(Icons.speed, color: _showTimelapseSettings ? Colors.amber : Colors.white, size: 20),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFilterCarousel() {
    final filters = presetFiltersList.take(15).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((preset) {
          final isSelected = _settings.activeFilter?.name == preset.name;
          final matrix = _presetToMatrix(preset);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _settings.activeFilter = null;
                } else {
                  _settings.activeFilter = preset;
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? Colors.amber : Colors.white30, width: isSelected ? 2 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (matrix != null)
                      ColorFiltered(
                        colorFilter: ColorFilter.matrix(matrix),
                        child: Image.asset('assets/filter_preview.png', fit: BoxFit.cover),
                      )
                    else
                      Image.asset('assets/filter_preview.png', fit: BoxFit.cover),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          preset.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildTimelapseSettingsUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _settings.timelapseIntervalSeconds,
            dropdownColor: Colors.grey[900],
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            items: [1, 2, 3, 5, 10].map((int val) {
              return DropdownMenuItem<int>(
                value: val,
                child: Text('${val}s gap'),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                _onSettingsChanged(_settings.copyWith(timelapseIntervalSeconds: val));
              }
            },
          ),
          const SizedBox(width: 12),
          const Icon(Icons.timelapse, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _settings.timelapseDurationSeconds,
            dropdownColor: Colors.grey[900],
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            items: const [
              DropdownMenuItem<int>(value: 0, child: Text('Infinite')),
              DropdownMenuItem<int>(value: 10, child: Text('10s')),
              DropdownMenuItem<int>(value: 30, child: Text('30s')),
              DropdownMenuItem<int>(value: 60, child: Text('1m')),
              DropdownMenuItem<int>(value: 300, child: Text('5m')),
            ],
            onChanged: (val) {
              if (val != null) {
                _onSettingsChanged(_settings.copyWith(timelapseDurationSeconds: val));
              }
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildBokehPill() {
    final fStops = ['f/1.4', 'f/2.0', 'f/2.8', 'f/4.0', 'f/8.0'];
    final blurForFStop = {'f/1.4': 1.0, 'f/2.0': 0.78, 'f/2.8': 0.6, 'f/4.0': 0.38, 'f/8.0': 0.18};

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isBokehExpanded)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: fStops.map((fStop) {
                  final isActive = _settings.bokehFStop == fStop;
                  return GestureDetector(
                    onTap: () {
                      final blur = blurForFStop[fStop] ?? 0.6;
                      setState(() {
                        _settings = _settings.copyWith(
                          bokehFStop: fStop,
                          bokehBlurLevel: blur,
                        );
                        _isBokehExpanded = false;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withAlpha(140),
                        border: Border.all(
                          color: isActive ? Colors.amber : Colors.white30,
                          width: isActive ? 2.0 : 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fStop,
                        style: TextStyle(
                          color: isActive ? Colors.amber : Colors.white70,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
          else
            GestureDetector(
              onTap: () {
                setState(() {
                  _isBokehExpanded = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white30, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _settings.bokehFStop,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildCaptureMethodRow() {
    final isPhotoLike = _settings.cameraMode == CameraMode.photo ||
        _settings.cameraMode == CameraMode.portrait;
    if (!isPhotoLike || _isRecordingVideo) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMethodChip(
              method: CaptureMethod.normal,
              icon: Icons.camera_alt_rounded,
              label: 'Shutter',
            ),
            _buildMethodChip(
              method: CaptureMethod.voice,
              icon: Icons.mic_rounded,
              label: 'Voice',
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }

  Widget _buildMethodChip({
    required CaptureMethod method,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _settings.captureMethod == method;
    return GestureDetector(
      onTap: _isProcessing ? null : () => _setCaptureMethod(method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              size: 14,
              color: isSelected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipButton() {
    return GestureDetector(
      onTap: _isProcessing || _isRecordingVideo || _timelapseState.isRecording ? null : _flipCamera,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(20),
        ),
        child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white38, size: 56),
            const SizedBox(height: 16),
            const Text('Camera & Microphone permissions required',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(50)
      ..strokeWidth = 0.8;

    for (int i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
