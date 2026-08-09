import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice-triggered shutter — listens for the keyword "cheese" (and common
/// mishearings: "cheeze", "chese", "please", "keys") then calls [onTriggered].
class VoiceCaptureService {
  final SpeechToText _speech = SpeechToText();

  bool _isListening = false;
  bool _initialized = false;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    try {
      _initialized = await _speech.initialize(
        onError: (_) => _isListening = false,
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _isListening = false;
        },
      );
    } catch (e) {
      debugPrint('VoiceCaptureService init error: $e');
    }
    return _initialized;
  }

  Future<void> startListening({required VoidCallback onTriggered}) async {
    if (!_initialized || _speech.isListening) return;
    _isListening = true;

    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        if (_matchesTrigger(words)) {
          _isListening = false;
          _speech.stop();
          onTriggered();
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.deviceDefault,
        cancelOnError: false,
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  bool _matchesTrigger(String words) {
    const triggers = ['cheese', 'cheeze', 'chese', 'cheee', 'please', 'keys'];
    return triggers.any(words.contains);
  }

  void dispose() {
    _speech.cancel();
  }
}
