import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Result from a completed burst capture + stack operation.
class StackResult {
  final Float64List accumulator;
  final int frameCount;
  final int width;
  final int height;

  StackResult({
    required this.accumulator,
    required this.frameCount,
    required this.width,
    required this.height,
  });
}

/// Handles burst frame capture and online pixel stacking with safety timeout.
/// Frames are accumulated into a running sum (Float64List) so memory is kept low.
class CaptureService {
  Float64List? _accumulator;
  int _frameCount = 0;
  int _width = 0;
  int _height = 0;
  bool _isCapturing = false;
  bool _streamStopped = false;
  Timer? _timeoutTimer;

  /// Capture [targetFrames] from the camera image stream, accumulate online,
  /// and return the averaged pixel data for enhancement.
  /// Includes a safety timeout (12s max) to prevent UI freezes.
  Future<StackResult?> captureAndStack({
    required CameraController controller,
    required int targetFrames,
    required void Function(int captured, int total) onProgress,
    required void Function(Uint8List rgba, int w, int h) onFirstFrame,
  }) async {
    _accumulator = null;
    _frameCount = 0;
    _isCapturing = true;
    _streamStopped = false;

    final completer = Completer<StackResult?>();

    void stopStreamAndComplete() async {
      if (_streamStopped) return;
      _streamStopped = true;
      _isCapturing = false;
      _timeoutTimer?.cancel();

      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('stopImageStream error (safely handled): $e');
      }

      if (_frameCount > 0 && _accumulator != null && !completer.isCompleted) {
        completer.complete(StackResult(
          accumulator: Float64List.fromList(_accumulator!),
          frameCount: _frameCount,
          width: _width,
          height: _height,
        ));
      } else if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    // Safety timeout: stop after 15s if stream callback stalls
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      debugPrint('CaptureService timeout safety triggered.');
      stopStreamAndComplete();
    });

    try {
      await controller.startImageStream((CameraImage image) {
        if (!_isCapturing || _streamStopped) return;

        _accumulateFrame(image);
        onProgress(_frameCount, targetFrames);

        // Hand off first frame raw RGBA for thumbnail preview
        if (_frameCount == 1) {
          _extractFirstFrameRgba(image).then((rgba) {
            if (rgba != null) onFirstFrame(rgba, image.width, image.height);
          });
        }

        if (_frameCount >= targetFrames) {
          stopStreamAndComplete();
        }
      });
    } catch (e) {
      debugPrint('startImageStream exception: $e');
      stopStreamAndComplete();
    }

    return completer.future;
  }

  void cancel() {
    _isCapturing = false;
    _streamStopped = true;
    _timeoutTimer?.cancel();
  }

  // ── Private ────────────────────────────────────────────────────────────

  void _accumulateFrame(CameraImage image) {
    final int w = image.width;
    final int h = image.height;

    if (_accumulator == null) {
      _width = w;
      _height = h;
      _accumulator = Float64List(w * h * 3);
    }

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;
    final int uvRowStride = uPlane.bytesPerRow;

    // Process pixels with step size of 1 for 100% detail accuracy
    for (int row = 0; row < h; row++) {
      final int yRowOffset = row * yPlane.bytesPerRow;
      final int uvRowOffset = (row >> 1) * uvRowStride;

      for (int col = 0; col < w; col++) {
        final int yIdx = yRowOffset + col;
        final int uvIdx = uvRowOffset + (col >> 1) * uvPixelStride;

        final int y = yPlane.bytes[yIdx] & 0xFF;
        final int u = (uPlane.bytes[uvIdx] & 0xFF) - 128;
        final int v = (vPlane.bytes[uvIdx] & 0xFF) - 128;

        final int r = (y + 1.402 * v).clamp(0, 255).toInt();
        final int g = (y - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt();
        final int b = (y + 1.772 * u).clamp(0, 255).toInt();

        final int pIdx = (row * w + col) * 3;
        _accumulator![pIdx] += r;
        _accumulator![pIdx + 1] += g;
        _accumulator![pIdx + 2] += b;
      }
    }
    _frameCount++;
  }

  Future<Uint8List?> _extractFirstFrameRgba(CameraImage image) async {
    try {
      return await compute(_yuvToRgba, _YuvParams(
        yBytes: Uint8List.fromList(image.planes[0].bytes),
        uBytes: Uint8List.fromList(image.planes[1].bytes),
        vBytes: Uint8List.fromList(image.planes[2].bytes),
        width: image.width,
        height: image.height,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 2,
      ));
    } catch (_) {
      return null;
    }
  }
}

// ── Isolate helpers ──────────────────────────────────────────────────────────

class _YuvParams {
  final Uint8List yBytes, uBytes, vBytes;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;

  _YuvParams({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });
}

/// Convert one YUV420 frame to raw RGBA bytes (runs in an isolate).
Uint8List _yuvToRgba(_YuvParams p) {
  final int total = p.width * p.height;
  final Uint8List rgba = Uint8List(total * 4);

  for (int row = 0; row < p.height; row++) {
    for (int col = 0; col < p.width; col++) {
      final int yIdx = row * p.yRowStride + col;
      final int uvIdx = (row >> 1) * p.uvRowStride + (col >> 1) * p.uvPixelStride;

      final int y = p.yBytes[yIdx] & 0xFF;
      final int u = (p.uBytes[uvIdx] & 0xFF) - 128;
      final int v = (p.vBytes[uvIdx] & 0xFF) - 128;

      final int r = (y + 1.402 * v).clamp(0, 255).toInt();
      final int g = (y - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt();
      final int b = (y + 1.772 * u).clamp(0, 255).toInt();

      final int pIdx = (row * p.width + col) * 4;
      rgba[pIdx] = r;
      rgba[pIdx + 1] = g;
      rgba[pIdx + 2] = b;
      rgba[pIdx + 3] = 255;
    }
  }
  return rgba;
}
