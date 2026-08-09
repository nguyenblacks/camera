import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ISP feature availability for the current device.
class IspFeatures {
  final int hwLevel;
  final bool supportsHdr;
  final bool supportsNight;
  final bool supportsHighQualityNR;
  final bool supportsHighQualityEdge;

  const IspFeatures({
    required this.hwLevel,
    required this.supportsHdr,
    required this.supportsNight,
    required this.supportsHighQualityNR,
    required this.supportsHighQualityEdge,
  });

  /// Hardware level names for logging/UI.
  String get hwLevelName {
    switch (hwLevel) {
      case 2: return 'FULL';
      case 3: return 'LEVEL_3';
      case 4: return 'LIMITED';
      default: return 'LEGACY';
    }
  }

  factory IspFeatures.fromMap(Map<Object?, Object?> map) {
    return IspFeatures(
      hwLevel: (map['hwLevel'] as int?) ?? 0,
      supportsHdr: (map['supportsHdr'] as bool?) ?? false,
      supportsNight: (map['supportsNight'] as bool?) ?? false,
      supportsHighQualityNR: (map['supportsHighQualityNR'] as bool?) ?? false,
      supportsHighQualityEdge: (map['supportsHighQualityEdge'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'IspFeatures(level=$hwLevelName, hdr=$supportsHdr, night=$supportsNight, '
      'hqNR=$supportsHighQualityNR, hqEdge=$supportsHighQualityEdge)';
}

/// Bridges to [Camera2CapturePlugin] on Android.
///
/// Usage pattern:
///   1. Dispose the Flutter CameraController (frees the camera hardware).
///   2. Call [captureHighQuality] — Camera2 opens, ISP-captures, closes.
///   3. Recreate the CameraController (preview resumes).
class NativeCaptureService {
  static const _channel = MethodChannel('com.swavoti.camera/camera2');

  static IspFeatures? _cachedFeatures;

  /// Query which ISP quality features are available on this device.
  /// Result is cached after the first call.
  static Future<IspFeatures> getSupportedFeatures({
    String cameraId = '0',
  }) async {
    if (_cachedFeatures != null) return _cachedFeatures!;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getSupportedFeatures',
        {'cameraId': cameraId},
      );
      if (raw != null) {
        _cachedFeatures = IspFeatures.fromMap(raw);
        debugPrint('ISP features: $_cachedFeatures');
        return _cachedFeatures!;
      }
    } catch (e) {
      debugPrint('getSupportedFeatures error: $e');
    }
    // Fallback: assume no advanced features (safe defaults)
    return const IspFeatures(
      hwLevel: 0,
      supportsHdr: false,
      supportsNight: false,
      supportsHighQualityNR: false,
      supportsHighQualityEdge: false,
    );
  }

  /// Opens Camera2, captures one ISP-optimised JPEG, returns the raw bytes.
  ///
  /// The caller MUST have disposed the Flutter CameraController first.
  /// On Helio G36, this triggers hardware MFNR, HDR/Night if OEM exposed them.
  static Future<Uint8List?> captureHighQuality({
    String cameraId = '0',
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'captureHighQuality',
        {'cameraId': cameraId},
      );
      return bytes;
    } on PlatformException catch (e) {
      debugPrint('NativeCaptureService error: ${e.code} — ${e.message}');
      return null;
    }
  }
}
