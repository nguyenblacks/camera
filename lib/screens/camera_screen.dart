import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

import '../models/camera_settings.dart';
import '../services/capture_service.dart';
import '../services/enhancement_service.dart';
import '../services/native_capture_service.dart';
import '../services/sound_service.dart';
import '../widgets/shutter_button.dart';
import '../widgets/thumbnail_widget.dart';
import '../widgets/top_menu_widget.dart';
import 'preview_screen.dart';
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
  final CaptureService _captureService = CaptureService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _permissionDenied = false;

  // Video recording state
  bool _isRecordingVideo = false;
  int _videoRecordSeconds = 0;
  Timer? _videoRecordTimer;

  // Thumbnail state
  Uint8List? _thumbnailBytes;
  ThumbnailState _thumbnailState = ThumbnailState.idle;
  Uint8List? _lastEnhancedBytes;

  // Processing progress
  int _capturedFrames = 0;
  int _totalFrames = 300;

  // Countdown timer
  int _countdownValue = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _videoRecordTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
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

      // Query hardware ISP capabilities (MediaTek Helio G36 MFNR, HDR, etc.)
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
    final prev = _controller;
    final newController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(_settings.flashMode);

      if (mounted) {
        setState(() {
          _controller = newController;
          _isInitialized = true;
        });
      }
      await prev?.dispose();
    } catch (e) {
      debugPrint('Controller setup error: $e');
      await newController.dispose();
    }
  }

  // ── Shutter Action Entry Point ─────────────────────────────────────────────

  Future<void> _onShutterPressed() async {
    if (_isProcessing || _controller == null) return;

    if (_settings.cameraMode == CameraMode.video) {
      _toggleVideoRecording();
      return;
    }

    // Photo mode countdown timer check
    if (_settings.timerSeconds > 0) {
      setState(() => _countdownValue = _settings.timerSeconds);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _countdownValue--);
        if (_countdownValue <= 0) {
          t.cancel();
          _startCapture();
        }
      });
      return;
    }

    _startCapture();
  }

  // ── Photo Capture Pipeline ────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (_controller == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _capturedFrames = 0;
      _totalFrames = _settings.frameCount;
      _thumbnailState = ThumbnailState.idle;
    });

    if (_settings.enableShutterSound) {
      SoundService.playShutterSound();
    }
    HapticFeedback.heavyImpact();

    try {
      Uint8List? finalJpeg;

      if (_settings.quality == PictureQuality.low) {
        // Single 100% hardware ISP capture (Instant, Sharp & Crystal Clear)
        final XFile file = await _controller!.takePicture();
        final rawBytes = await file.readAsBytes();

        if (mounted) {
          setState(() {
            _thumbnailBytes = rawBytes;
            _thumbnailState = ThumbnailState.processing;
          });
        }

        // Apply warmth balance + super clarity sharpening + EXIF orientation baking
        finalJpeg = await EnhancementService.enhanceSingleFrame(rawBytes);
        try {
          File(file.path).delete();
        } catch (_) {}
      } else {
        // Multi-frame burst stack capture
        final result = await _captureService.captureAndStack(
          controller: _controller!,
          targetFrames: _settings.frameCount,
          onProgress: (captured, total) {
            if (mounted) {
              setState(() {
                _capturedFrames = captured;
                _totalFrames = total;
              });
            }
          },
          onFirstFrame: (rgba, w, h) {
            EnhancementService.encodeRgbaToJpeg(rgba, w, h).then((jpeg) {
              if (jpeg != null && mounted) {
                setState(() {
                  _thumbnailBytes = jpeg;
                  _thumbnailState = ThumbnailState.processing;
                });
              }
            });
          },
        );

        if (result != null) {
          finalJpeg = await EnhancementService.process(
            accumulator: result.accumulator,
            frameCount: result.frameCount,
            width: result.width,
            height: result.height,
          );
        }
      }

      if (finalJpeg != null) {
        await _saveToGallery(finalJpeg);
      }

      _finishProcessing(finalJpeg);
    } catch (e) {
      debugPrint('Capture error: $e');
      _finishProcessing(null);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _saveToGallery(Uint8List jpegBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/swavoti_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpegBytes);
      await Gal.putImage(file.path, album: 'Swavoti Camera');
      await file.delete();
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  void _finishProcessing(Uint8List? enhanced) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isProcessing = false;
      _lastEnhancedBytes = enhanced;
      _thumbnailBytes = enhanced ?? _thumbnailBytes;
      _thumbnailState = ThumbnailState.done;
      _capturedFrames = 0;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _thumbnailState = ThumbnailState.idle);
    });
  }

  // ── Video Recording Pipeline ──────────────────────────────────────────────

  Future<void> _toggleVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecordingVideo) {
      // Stop recording
      try {
        final XFile videoFile = await _controller!.stopVideoRecording();
        _videoRecordTimer?.cancel();

        setState(() {
          _isRecordingVideo = false;
          _videoRecordSeconds = 0;
        });

        // Save to gallery
        await Gal.putVideo(videoFile.path, album: 'Swavoti Camera');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video saved to Gallery'),
              backgroundColor: Color(0xFF222222),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Stop video error: $e');
        setState(() {
          _isRecordingVideo = false;
          _videoRecordSeconds = 0;
        });
      }
    } else {
      // Start recording
      try {
        await _controller!.startVideoRecording();
        HapticFeedback.mediumImpact();
        if (_settings.enableShutterSound) {
          SoundService.playShutterSound();
        }

        setState(() {
          _isRecordingVideo = true;
          _videoRecordSeconds = 0;
        });

        _videoRecordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          setState(() => _videoRecordSeconds++);
        });
      } catch (e) {
        debugPrint('Start video error: $e');
      }
    }
  }

  // ── Settings & Flip Logic ──────────────────────────────────────────────────

  Future<void> _flipCamera() async {
    if (_isProcessing || _isRecordingVideo || _cameras.length < 2) return;
    final newSettings = _settings.copyWith(isFrontCamera: !_settings.isFrontCamera);
    setState(() => _settings = newSettings);

    final target = newSettings.isFrontCamera
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first)
        : _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first);

    setState(() => _isInitialized = false);
    await _setupController(target);
  }

  void _onSettingsChanged(CameraSettings newSettings) async {
    setState(() => _settings = newSettings);
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller!.setFlashMode(newSettings.flashMode);
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

  // ── Build Method ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) return _buildPermissionDenied();
    if (!_isInitialized || _controller == null) return _buildLoading();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // ── Camera preview with aspect ratio letterboxing ──────────────
          _buildPreviewWithAspectRatio(),

          // ── Grid overlay ─────────────────────────────────────────────
          if (_settings.showGrid) _buildGrid(),

          // ── Video recording duration timer indicator ──────────────────
          if (_isRecordingVideo) _buildVideoTimer(),

          // ── Photo countdown overlay ───────────────────────────────────
          if (_countdownValue > 0) _buildCountdown(),

          // ── Processing progress bar ───────────────────────────────────
          if (_isProcessing && _capturedFrames > 0 && _capturedFrames < _totalFrames)
            _buildProgressBar(),

          // ── Controls overlay ──────────────────────────────────────────
          SafeArea(child: _buildControls()),
        ],
      ),
    );
  }

  // ── Sub-builders ─────────────────────────────────────────────────────────

  Widget _buildPreviewWithAspectRatio() {
    final double? targetRatio = _settings.aspectRatioRatio;

    Widget previewWidget = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.previewSize!.height,
        height: _controller!.value.previewSize!.width,
        child: CameraPreview(_controller!),
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
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(duration: 500.ms),
            const SizedBox(width: 8),
            Text(
              '$mins:$secs',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildCountdown() {
    return Center(
      child: Text(
        '$_countdownValue',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 120,
          fontWeight: FontWeight.w200,
          shadows: [Shadow(color: Colors.black54, blurRadius: 20)],
        ),
      ).animate(key: ValueKey(_countdownValue)).scale(
            begin: const Offset(1.3, 1.3),
            end: const Offset(1.0, 1.0),
            duration: 400.ms,
            curve: Curves.easeOut,
          ),
    );
  }

  Widget _buildProgressBar() {
    final pct = _capturedFrames / _totalFrames;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: LinearProgressIndicator(
        value: pct,
        backgroundColor: Colors.white12,
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
        minHeight: 3,
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        // ── Top bar: flash + menu + gear ──────────────────────────────
        TopMenuWidget(
          settings: _settings,
          onSettingsChanged: _onSettingsChanged,
          onOpenSettings: _openSettingsScreen,
        ),

        const Spacer(),

        // ── Photo / Video mode selector ────────────────────────────────
        _buildModeSelector(),

        const SizedBox(height: 16),

        // ── Bottom bar ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Flip camera (left)
              _buildFlipButton(),

              // Shutter button (center)
              ShutterButton(
                onPressed: _isProcessing ? null : _onShutterPressed,
                isProcessing: _isProcessing,
                isVideoMode: _settings.cameraMode == CameraMode.video,
                isRecording: _isRecordingVideo,
              ),

              // Thumbnail (right)
              ThumbnailWidget(
                imageBytes: _thumbnailBytes,
                state: _thumbnailState,
                onTap: _lastEnhancedBytes != null
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PreviewScreen(
                              imageBytes: _lastEnhancedBytes!,
                            ),
                          ),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeChip(CameraMode.photo, 'PHOTO'),
          _buildModeChip(CameraMode.video, 'VIDEO'),
        ],
      ),
    );
  }

  Widget _buildModeChip(CameraMode mode, String label) {
    final isSelected = _settings.cameraMode == mode;
    return GestureDetector(
      onTap: _isProcessing || _isRecordingVideo
          ? null
          : () => _onSettingsChanged(_settings.copyWith(cameraMode: mode)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildFlipButton() {
    return GestureDetector(
      onTap: _isProcessing || _isRecordingVideo ? null : _flipCamera,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(20),
        ),
        child: const Icon(
          Icons.flip_camera_android_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.amber,
          strokeWidth: 1.5,
        ),
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
            const Text(
              'Camera & Microphone permissions required',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid painter ─────────────────────────────────────────────────────────────

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
