import 'dart:async';
import 'package:flutter/foundation.dart';

class TimelapseState {
  final bool isRecording;
  final int capturedFrames;
  final int elapsedSeconds;

  const TimelapseState({
    required this.isRecording,
    required this.capturedFrames,
    required this.elapsedSeconds,
  });
}

/// Service that coordinates periodic frame triggers for TIMELAPSE mode.
class TimelapseService {
  Timer? _intervalTimer;
  Timer? _durationTimer;
  int _capturedFrames = 0;
  int _elapsedSeconds = 0;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  int get capturedFrames => _capturedFrames;
  int get elapsedSeconds => _elapsedSeconds;

  void start({
    required int intervalSeconds,
    required Future<void> Function() onFrameTrigger,
    required void Function(TimelapseState state) onUpdate,
  }) {
    if (_isRecording) return;

    _isRecording = true;
    _capturedFrames = 0;
    _elapsedSeconds = 0;

    onUpdate(TimelapseState(
      isRecording: true,
      capturedFrames: 0,
      elapsedSeconds: 0,
    ));

    // Frame capture timer
    _intervalTimer = Timer.periodic(
      Duration(seconds: intervalSeconds.clamp(1, 10)),
      (_) async {
        if (!_isRecording) return;
        _capturedFrames++;
        onUpdate(TimelapseState(
          isRecording: true,
          capturedFrames: _capturedFrames,
          elapsedSeconds: _elapsedSeconds,
        ));
        await onFrameTrigger();
      },
    );

    // Elapsed duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRecording) return;
      _elapsedSeconds++;
      onUpdate(TimelapseState(
        isRecording: true,
        capturedFrames: _capturedFrames,
        elapsedSeconds: _elapsedSeconds,
      ));
    });
  }

  void stop({required void Function(TimelapseState state) onUpdate}) {
    _isRecording = false;
    _intervalTimer?.cancel();
    _durationTimer?.cancel();

    onUpdate(TimelapseState(
      isRecording: false,
      capturedFrames: _capturedFrames,
      elapsedSeconds: _elapsedSeconds,
    ));
  }
}
