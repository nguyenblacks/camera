import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detected face rectangle in preview coordinates (0..1 normalized).
class DetectedFace {
  final Rect normalizedRect;
  DetectedFace(this.normalizedRect);
}

/// Service that processes camera image stream frames through Google ML Kit
/// face detection. Only used on front camera (selfie mode).
class FaceDetectionService {
  FaceDetector? _detector;
  bool _isProcessing = false;
  bool _isActive = false;

  /// Current detected faces (normalized 0..1 coordinates).
  final ValueNotifier<List<DetectedFace>> faces =
      ValueNotifier<List<DetectedFace>>([]);

  void initialize() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
    _isActive = true;
  }

  /// Start processing frames from the camera image stream.
  /// Call this with each CameraImage from controller.startImageStream().
  Future<void> processImage(CameraImage image, CameraDescription camera) async {
    if (!_isActive || _isProcessing || _detector == null) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final detectedFaces = await _detector!.processImage(inputImage);

      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();

      faces.value = detectedFaces.map((face) {
        // Normalize the bounding box to 0..1
        final rect = face.boundingBox;
        return DetectedFace(Rect.fromLTRB(
          (rect.left / imageWidth).clamp(0.0, 1.0),
          (rect.top / imageHeight).clamp(0.0, 1.0),
          (rect.right / imageWidth).clamp(0.0, 1.0),
          (rect.bottom / imageHeight).clamp(0.0, 1.0),
        ));
      }).toList();
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    // Use NV21 format on Android (most common from camera plugin)
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Determine rotation based on sensor orientation
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    // For NV21/YUV420 we use the first plane's bytes
    if (image.planes.isEmpty) return null;

    final bytes = image.planes.first.bytes;
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  /// Clear faces and stop processing.
  void stop() {
    _isActive = false;
    faces.value = [];
  }

  /// Resume processing after stop().
  void resume() {
    _isActive = true;
  }

  Future<void> dispose() async {
    _isActive = false;
    faces.value = [];
    await _detector?.close();
    _detector = null;
  }
}
