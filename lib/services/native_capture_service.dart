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

/// Hardware video capabilities (max resolution, FPS, supported resolution list).
class HardwareVideoCaps {
  final String maxResolution;
  final int maxFps;
  final bool has4K;
  final bool has1080p;
  final bool has720p;
  final List<String> supportedResolutions;

  const HardwareVideoCaps({
    required this.maxResolution,
    required this.maxFps,
    required this.has4K,
    required this.has1080p,
    required this.has720p,
    required this.supportedResolutions,
  });

  factory HardwareVideoCaps.fromMap(Map<Object?, Object?> map) {
    final rawResolutions = map['supportedResolutions'];
    final resolutions = <String>[];
    if (rawResolutions is List) {
      for (final item in rawResolutions) {
        resolutions.add(item.toString());
      }
    }
    if (resolutions.isEmpty) {
      if ((map['has4K'] as bool?) ?? false) resolutions.add('4K');
      if ((map['has1080p'] as bool?) ?? false) resolutions.add('1080p');
      if ((map['has720p'] as bool?) ?? false) resolutions.add('720p');
    }
    return HardwareVideoCaps(
      maxResolution: (map['maxResolution'] as String?) ?? '1080p',
      maxFps: (map['maxFps'] as int?) ?? 30,
      has4K: (map['has4K'] as bool?) ?? false,
      has1080p: (map['has1080p'] as bool?) ?? true,
      has720p: (map['has720p'] as bool?) ?? true,
      supportedResolutions: resolutions,
    );
  }

  /// Plain text summary of hardware capabilities, e.g. "1080p @ 30fps"
  String get displayCapsText => '$maxResolution @ ${maxFps}fps';
}

/// Result from a native DNG capture.
class DngCaptureResult {
  final Uint8List dngBytes;
  final int width;
  final int height;

  const DngCaptureResult({
    required this.dngBytes,
    required this.width,
    required this.height,
  });
}

/// Bridges to [Camera2CapturePlugin] on Android.
///
/// Usage pattern:
///   1. Dispose the Flutter CameraController (frees the camera hardware).
///   2. Call [captureHighQuality] or [captureDng] — Camera2 opens, captures, closes.
///   3. Recreate the CameraController (preview resumes).
class NativeCaptureService {
  static const _channel = MethodChannel('com.swavoti.camera/camera2');

  static IspFeatures? _cachedFeatures;
  static bool? _cachedRawSupport;
  static final Map<String, HardwareVideoCaps> _videoCapsCache = {};

  /// Query hardware video capabilities for the specified camera (front vs back).
  static Future<HardwareVideoCaps> getVideoCapabilities({
    required String cameraId,
  }) async {
    if (_videoCapsCache.containsKey(cameraId)) {
      return _videoCapsCache[cameraId]!;
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getVideoCapabilities',
        {'cameraId': cameraId},
      );
      if (raw != null) {
        final caps = HardwareVideoCaps.fromMap(raw);
        _videoCapsCache[cameraId] = caps;
        return caps;
      }
    } catch (e) {
      debugPrint('getVideoCapabilities error: $e');
    }
    const fallback = HardwareVideoCaps(
      maxResolution: '1080p',
      maxFps: 30,
      has4K: false,
      has1080p: true,
      has720p: true,
      supportedResolutions: ['1080p', '720p'],
    );
    _videoCapsCache[cameraId] = fallback;
    return fallback;
  }

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

  /// Checks if the camera hardware supports true RAW_SENSOR / DNG capture.
  /// Result is cached after the first call.
  static Future<bool> supportsRawCapture({String cameraId = '0'}) async {
    if (_cachedRawSupport != null) return _cachedRawSupport!;
    try {
      final supported = await _channel.invokeMethod<bool>(
        'supportsRawCapture',
        {'cameraId': cameraId},
      );
      _cachedRawSupport = supported ?? false;
    } catch (e) {
      debugPrint('supportsRawCapture error: $e');
      _cachedRawSupport = false;
    }
    return _cachedRawSupport!;
  }

  /// Opens Camera2, captures a true RAW_SENSOR frame, and returns it encoded
  /// as a DNG file using Android's built-in DngCreator.
  ///
  /// The caller MUST have disposed the Flutter CameraController first.
  /// Returns null if the device does not support RAW capture, in which case
  /// [captureHighQuality] (JPEG) should be used as fallback.
  static Future<DngCaptureResult?> captureDng({String cameraId = '0'}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'captureDng',
        {'cameraId': cameraId},
      );
      if (raw == null) return null;
      final dngBytes = raw['dngBytes'];
      if (dngBytes == null) return null;
      return DngCaptureResult(
        dngBytes: dngBytes is Uint8List ? dngBytes : Uint8List.fromList((dngBytes as List).cast<int>()),
        width: (raw['width'] as int?) ?? 0,
        height: (raw['height'] as int?) ?? 0,
      );
    } on PlatformException catch (e) {
      debugPrint('captureDng error: ${e.code} — ${e.message}');
      return null;
    }
  }
}
