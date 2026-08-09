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

import '../models/camera_settings.dart';
import '../services/device_info_service.dart';
import '../services/enhancement_service.dart';
import '../services/native_capture_service.dart';
import '../services/sound_service.dart';
import '../services/voice_capture_service.dart';
import '../widgets/shutter_button.dart';
import '../widgets/thumbnail_widget.dart';
import '../widgets/top_menu_widget.dart';
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

  // Thumbnail state
  Uint8List? _thumbnailBytes;
  ThumbnailState _thumbnailState = ThumbnailState.idle;
  String? _lastSavedFilePath;

  // Countdown timer
  int _countdownValue = 0;
  Timer? _countdownTimer;

  // Palm shutter state
  bool _palmStreamActive = false;
  bool _palmDetected = false;
  int _palmCountdown = 0;
  Timer? _palmCountdownTimer;
  int _palmFrameSkip = 0;

  // Voice shutter
  final VoiceCaptureService _voiceService = VoiceCaptureService();
  bool _voiceListening = false;

  // Device info
  String _deviceModel = '';

  // Filter carousel overlay toggle
  bool _showFilterCarousel = false;

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
    _palmCountdownTimer?.cancel();
    _voiceService.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopPalmStream();
      _voiceService.stopListening();
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

  // ── Shutter action entry point ────────────────────────────────────────────

  Future<void> _onShutterPressed() async {
    if (_isProcessing || _controller == null) return;

    if (_settings.cameraMode == CameraMode.video) {
      _toggleVideoRecording();
      return;
    }

    if (_settings.timerSeconds > 0 && _settings.captureMethod == CaptureMethod.normal) {
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

  // ── Photo capture ─────────────────────────────────────────────────────────

  Future<void> _startCapture() async {
    if (_controller == null || _isProcessing) return;

    if (_palmStreamActive) await _stopPalmStream();

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

      Uint8List? raw2;
      if (_settings.usesTwoFrames) {
        await Future.delayed(const Duration(milliseconds: 180));
        final XFile f2 = await _controller!.takePicture();
        raw2 = await f2.readAsBytes();
        try { File(f2.path).deleteSync(); } catch (_) {}
      }

      final finalJpeg = await EnhancementService.enhanceWithQuality(
        frame1: raw1,
        frame2: raw2,
        quality: _settings.quality,
        deviceModel: _settings.watermarkEnabled ? _deviceModel : null,
        filter: _settings.filter,
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
    }
  }

  Future<void> _saveToGallery(Uint8List jpegBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/swavoti_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpegBytes);
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

    if (_settings.captureMethod == CaptureMethod.palm) {
      Future.delayed(const Duration(milliseconds: 600), _startPalmStream);
    } else if (_settings.captureMethod == CaptureMethod.voice && !_voiceListening) {
      Future.delayed(const Duration(milliseconds: 600), _startVoiceListening);
    }
  }

  // ── Palm shutter ──────────────────────────────────────────────────────────

  Future<void> _startPalmStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_palmStreamActive || _isProcessing) return;

    try {
      _palmStreamActive = true;
      _palmDetected = false;
      _palmFrameSkip = 0;

      await _controller!.startImageStream((CameraImage frame) {
        if (!_palmStreamActive || _palmDetected) return;

        _palmFrameSkip++;
        if (_palmFrameSkip % 4 != 0) return;

        final detected = _checkPalmInFrame(frame);
        if (detected && !_palmDetected) {
          _palmDetected = true;
          _startPalmCountdown();
        }
      });
    } catch (e) {
      debugPrint('Palm stream error: $e');
      _palmStreamActive = false;
    }
  }

  Future<void> _stopPalmStream() async {
    if (!_palmStreamActive) return;
    _palmStreamActive = false;
    _palmDetected = false;
    _palmCountdownTimer?.cancel();
    if (mounted) setState(() => _palmCountdown = 0);

    try {
      await _controller?.stopImageStream();
    } catch (_) {}
  }

  void _startPalmCountdown() {
    if (mounted) setState(() => _palmCountdown = 3);

    _palmCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _palmCountdown--);
      if (_palmCountdown <= 0) {
        t.cancel();
        _stopPalmStream().then((_) => _startCapture());
      }
    });
  }

  bool _checkPalmInFrame(CameraImage frame) {
    try {
      final int w = frame.width;
      final int h = frame.height;
      final yPlane = frame.planes[0];
      final uPlane = frame.planes[1];
      final vPlane = frame.planes[2];
      final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

      final int startCol = w ~/ 3;
      final int endCol = w * 2 ~/ 3;
      final int startRow = h ~/ 3;
      final int endRow = h * 2 ~/ 3;
      final int stepCol = (endCol - startCol) ~/ 20;
      final int stepRow = (endRow - startRow) ~/ 20;

      int skinCount = 0, total = 0;

      for (int row = startRow; row < endRow; row += stepRow.clamp(1, 999)) {
        for (int col = startCol; col < endCol; col += stepCol.clamp(1, 999)) {
          final int yIdx = row * yPlane.bytesPerRow + col;
          final int uvRow = (row >> 1) * uPlane.bytesPerRow;
          final int uvCol = (col >> 1) * uvPixelStride;

          if (yIdx >= yPlane.bytes.length) continue;
          if (uvRow + uvCol >= uPlane.bytes.length) continue;

          final int y = yPlane.bytes[yIdx] & 0xFF;
          final int u = (uPlane.bytes[uvRow + uvCol] & 0xFF) - 128;
          final int v = (vPlane.bytes[uvRow + uvCol] & 0xFF) - 128;

          final int r = (y + 1.402 * v).clamp(0, 255).toInt();
          final int g = (y - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt();
          final int b = (y + 1.772 * u).clamp(0, 255).toInt();

          if (r > 80 && g > 40 && b > 20 && r > g && r > b &&
              (r - g).abs() > 10 && r < 250) {
            skinCount++;
          }
          total++;
        }
      }

      return total > 0 && (skinCount / total) >= 0.38;
    } catch (_) {
      return false;
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

  // ── Capture method toggle ─────────────────────────────────────────────────

  Future<void> _setCaptureMethod(CaptureMethod method) async {
    if (_settings.captureMethod == CaptureMethod.palm) await _stopPalmStream();
    if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();

    final newSettings = _settings.copyWith(captureMethod: method);
    setState(() => _settings = newSettings);

    if (method == CaptureMethod.palm) {
      await _startPalmStream();
    } else if (method == CaptureMethod.voice) {
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

    if (_settings.captureMethod == CaptureMethod.palm) await _stopPalmStream();
    if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();

    final newSettings = _settings.copyWith(isFrontCamera: !_settings.isFrontCamera);

    final target = newSettings.isFrontCamera
        ? _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first)
        : _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first);

    setState(() => _settings = newSettings);
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
          if (_countdownValue > 0) _buildCountdown(),
          if (_palmCountdown > 0) _buildPalmCountdown(),
          if (_voiceListening) _buildVoiceOverlay(),

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

  Widget _buildPalmCountdown() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.back_hand_outlined, color: Colors.white, size: 64),
          const SizedBox(height: 8),
          Text(
            '$_palmCountdown',
            style: const TextStyle(
              color: Colors.white, fontSize: 100, fontWeight: FontWeight.w200,
              shadows: [Shadow(color: Colors.black54, blurRadius: 20)],
            ),
          ).animate(key: ValueKey(_palmCountdown)).scale(
                begin: const Offset(1.3, 1.3), end: const Offset(1.0, 1.0),
                duration: 400.ms, curve: Curves.easeOut),
        ],
      ),
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
        ),
        const Spacer(),

        // Photo filter horizontal carousel overlay
        if (_showFilterCarousel) _buildFilterCarouselOverlay(),

        _buildModeSelector(),
        const SizedBox(height: 12),
        _buildCaptureMethodRow(),
        const SizedBox(height: 16),

        // Bottom control row with shutter + floating magic wand filter button
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildFlipButton(),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  ShutterButton(
                    onPressed: _isProcessing ? null : _onShutterPressed,
                    isProcessing: _isProcessing,
                    isVideoMode: _settings.cameraMode == CameraMode.video,
                    isRecording: _isRecordingVideo,
                  ),
                  // Floating magic wand / filter button (positioned top right of shutter)
                  if (!_isRecordingVideo && _settings.cameraMode == CameraMode.photo)
                    Positioned(
                      right: -24,
                      top: -6,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showFilterCarousel = !_showFilterCarousel);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _settings.filter != CameraFilter.none || _showFilterCarousel
                                ? Colors.amber
                                : Colors.black87,
                            border: Border.all(
                              color: Colors.white.withAlpha(200),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(120),
                                blurRadius: 6,
                              )
                            ],
                          ),
                          child: Icon(
                            Icons.auto_fix_high_rounded,
                            size: 18,
                            color: _settings.filter != CameraFilter.none || _showFilterCarousel
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _buildThumbnail(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Photo filter carousel ──────────────────────────────────────────────────

  Widget _buildFilterCarouselOverlay() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(215),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Photo Filters',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showFilterCarousel = false),
                  child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: CameraFilter.values.map((f) => _buildFilterSquare(f)).toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildFilterSquare(CameraFilter f) {
    final isSelected = _settings.filter == f;

    // Custom gradient for each filter square preview
    LinearGradient gradient;
    switch (f) {
      case CameraFilter.none:
        gradient = const LinearGradient(colors: [Color(0xFF444444), Color(0xFF222222)]);
        break;
      case CameraFilter.warm:
        gradient = const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFFF5722)]);
        break;
      case CameraFilter.cool:
        gradient = const LinearGradient(colors: [Color(0xFF03A9F4), Color(0xFF00BCD4)]);
        break;
      case CameraFilter.vivid:
        gradient = const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFF9C27B0)]);
        break;
      case CameraFilter.noir:
        gradient = const LinearGradient(colors: [Color(0xFF888888), Color(0xFF111111)]);
        break;
      case CameraFilter.sepia:
        gradient = const LinearGradient(colors: [Color(0xFF8D6E63), Color(0xFF3E2723)]);
        break;
      case CameraFilter.dramatic:
        gradient = const LinearGradient(colors: [Color(0xFF37474F), Color(0xFF212121)]);
        break;
      case CameraFilter.cyber:
        gradient = const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFFD500F9)]);
        break;
      case CameraFilter.fade:
        gradient = const LinearGradient(colors: [Color(0xFF90A4AE), Color(0xFF546E7A)]);
        break;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _onSettingsChanged(_settings.copyWith(filter: f));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? Colors.amber : Colors.white24,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [const BoxShadow(color: Colors.amber, blurRadius: 6)]
                    : null,
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              f.label,
              style: TextStyle(
                color: isSelected ? Colors.amber : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
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
          : () async {
              if (_settings.captureMethod == CaptureMethod.palm) await _stopPalmStream();
              if (_settings.captureMethod == CaptureMethod.voice) await _stopVoiceListening();
              _onSettingsChanged(_settings.copyWith(cameraMode: mode));
            },
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
            fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureMethodRow() {
    if (_settings.cameraMode == CameraMode.video || _isRecordingVideo) {
      return const SizedBox.shrink();
    }

    return Container(
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
            method: CaptureMethod.palm,
            icon: Icons.back_hand_outlined,
            label: 'Palm',
          ),
          _buildMethodChip(
            method: CaptureMethod.voice,
            icon: Icons.mic_rounded,
            label: 'Voice',
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
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
      onTap: _isProcessing || _isRecordingVideo ? null : _flipCamera,
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
