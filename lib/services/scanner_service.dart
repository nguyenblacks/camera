import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class ScannerService {
  BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  bool _isProcessing = false;
  bool _isStopped = false;

  /// The most recently detected QR URL. Null when nothing is in frame.
  final ValueNotifier<String?> detectedUrl = ValueNotifier(null);

  void processImage(CameraImage image, CameraDescription camera) async {
    if (_isProcessing || _isStopped) return;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final barcodes = await _barcodeScanner.processImage(inputImage);

      String? foundUrl;
      for (final barcode in barcodes) {
        if (barcode.type == BarcodeType.url) {
          foundUrl = barcode.url?.url;
        } else if (barcode.rawValue != null && barcode.rawValue!.startsWith('http')) {
          foundUrl = barcode.rawValue;
        }
        if (foundUrl != null) break;
      }

      // Update notifier only when value actually changes
      if (detectedUrl.value != foundUrl) {
        detectedUrl.value = foundUrl;
      }
    } catch (e) {
      debugPrint('QR scan error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Pause scanning (called before photo capture or video recording).
  void stop() {
    _isStopped = true;
    // Clear the overlay immediately when we stop scanning
    detectedUrl.value = null;
    _barcodeScanner.close();
    // Recreate scanner so it's ready for the next start()
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  }

  /// Resume scanning (called after returning to preview).
  void resume() {
    _isStopped = false;
  }

  /// Full teardown — only call when the camera screen is fully disposed.
  void dispose() {
    _barcodeScanner.close();
    detectedUrl.dispose();
  }

  InputImage? _buildInputImage(CameraImage image, CameraDescription camera) {
    // For multi-plane formats (YUV420), only use the Y (luminance) plane
    // since ML Kit only needs it for barcode detection.
    final Plane yPlane = image.planes[0];

    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    final inputImageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (inputImageRotation == null) return null;

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      imageRotation: inputImageRotation,
      format: inputImageFormat,
      bytesPerRow: yPlane.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: yPlane.bytes, metadata: metadata);
  }
}
