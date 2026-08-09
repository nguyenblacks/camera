import 'package:flutter/services.dart';

class SoundService {
  static const _channel = MethodChannel('com.swavoti.camera/camera2');

  /// Plays the shutter click sound using native Android MediaActionSound.
  static Future<void> playShutterSound() async {
    try {
      await _channel.invokeMethod('playShutterSound');
    } catch (_) {
      // Fallback: silent if audio fails
    }
  }
}
