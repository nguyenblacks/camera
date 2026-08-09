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
import '../widgets/shutter_button.dart';
import '../widgets/thumbnail_widget.dart';
import '../widgets/top_menu_widget.dart';
import 'preview_screen.dart';

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
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
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
      ResolutionPreset.medium,
      enableAudio: false,
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

  Future<void> _onShutterPressed() async {
    if (_isProcessing || _controller == null) return;

    // Handle countdown timer
    if (_settings.timerSeconds > 0) {
      setState(() => _countdownValue = _settings.timerSeconds);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
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

  Future<void> _startCapture() async {
    if (_controller == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _capturedFrames = 0;
      _totalFrames = _settings.frameCount;
      _thumbnailState = ThumbnailState.idle;
    });

    HapticFeedback.heavyImpact();

    try {
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
          // Encode RGBA → JPEG in background then show in thumbnail
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

      if (result == null) {
        _finishProcessing(null);
        return;
      }

      // Run enhancement in isolate
      final enhanced = await EnhancementService.process(
        accumulator: result.accumulator,
        frameCount: result.frameCount,
        width: result.width,
        height: result.height,
      );

      if (enhanced != null) {
        await _saveToGallery(enhanced);
      }

      _finishProcessing(enhanced);
    } catch (e) {
      debugPrint('Capture error: $e');
      _finishProcessing(null);
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

    // Revert thumbnail state to idle after a moment
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _thumbnailState = ThumbnailState.idle);
    });
  }

  Future<void> _flipCamera() async {
    if (_isProcessing || _cameras.length < 2) return;
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

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) return _buildPermissionDenied();
    if (!_isInitialized || _controller == null) return _buildLoading();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera preview ────────────────────────────────────────────
          _buildPreview(),

          // ── Grid overlay ─────────────────────────────────────────────
          if (_settings.showGrid) _buildGrid(),

          // ── Countdown overlay ─────────────────────────────────────────
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

  Widget _buildPreview() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize!.height,
          height: _controller!.value.previewSize!.width,
          child: CameraPreview(_controller!),
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
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        minHeight: 2,
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        // ── Top bar: flash + menu (top-left) ─────────────────────────
        Align(
          alignment: Alignment.topLeft,
          child: TopMenuWidget(
            settings: _settings,
            onSettingsChanged: _onSettingsChanged,
          ),
        ),

        const Spacer(),

        // ── Bottom bar ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Flip camera (left)
              _buildFlipButton(),

              // Shutter (center)
              ShutterButton(
                onPressed: _isProcessing ? null : _onShutterPressed,
                isProcessing: _isProcessing,
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

  Widget _buildFlipButton() {
    return GestureDetector(
      onTap: _isProcessing ? null : _flipCamera,
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
          color: Colors.white,
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
              'Camera permission required',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.white)),
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

    // 2 vertical lines, 2 horizontal lines (rule of thirds)
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
