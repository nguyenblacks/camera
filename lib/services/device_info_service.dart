import 'package:flutter/services.dart';

/// Reads device model name and system ringtones via the Camera2 method channel.
class DeviceInfoService {
  static const _channel = MethodChannel('com.swavoti.camera/camera2');

  static String? _cachedModel;

  /// Returns e.g. "Xiaomi Redmi A3" or "Samsung Galaxy A05".
  static Future<String> getDeviceModel() async {
    if (_cachedModel != null) return _cachedModel!;
    try {
      final model = await _channel.invokeMethod<String>('getDeviceModel');
      _cachedModel = model ?? 'Unknown Device';
    } catch (_) {
      _cachedModel = 'Unknown Device';
    }
    return _cachedModel!;
  }

  /// Returns a list of notification-category ringtones from RingtoneManager.
  /// Each entry: {'title': String, 'uri': String}
  static Future<List<Map<String, String>>> getNotificationRingtones() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getNotificationRingtones');
      if (raw == null) return [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map((m) => {
                'title': (m['title'] as String?) ?? 'Unknown',
                'uri': (m['uri'] as String?) ?? '',
              })
          .where((m) => m['uri']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
