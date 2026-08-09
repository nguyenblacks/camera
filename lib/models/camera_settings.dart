import 'package:camera/camera.dart';

enum BurstCount { frames30, frames100, frames300 }

enum TimerDelay { off, three, ten }

enum AspectRatioMode { ratio4x3, ratio16x9, ratio1x1 }

class CameraSettings {
  FlashMode flashMode;
  TimerDelay timerDelay;
  BurstCount burstCount;
  AspectRatioMode aspectRatio;
  bool showGrid;
  bool isFrontCamera;

  CameraSettings({
    this.flashMode = FlashMode.off,
    this.timerDelay = TimerDelay.off,
    this.burstCount = BurstCount.frames300,
    this.aspectRatio = AspectRatioMode.ratio4x3,
    this.showGrid = false,
    this.isFrontCamera = false,
  });

  int get frameCount {
    switch (burstCount) {
      case BurstCount.frames30:
        return 30;
      case BurstCount.frames100:
        return 100;
      case BurstCount.frames300:
        return 300;
    }
  }

  int get timerSeconds {
    switch (timerDelay) {
      case TimerDelay.off:
        return 0;
      case TimerDelay.three:
        return 3;
      case TimerDelay.ten:
        return 10;
    }
  }

  String get flashLabel {
    switch (flashMode) {
      case FlashMode.off:
        return 'Off';
      case FlashMode.auto:
        return 'Auto';
      case FlashMode.always:
        return 'On';
      case FlashMode.torch:
        return 'Torch';
    }
  }

  String get timerLabel {
    switch (timerDelay) {
      case TimerDelay.off:
        return 'Off';
      case TimerDelay.three:
        return '3s';
      case TimerDelay.ten:
        return '10s';
    }
  }

  String get burstLabel {
    switch (burstCount) {
      case BurstCount.frames30:
        return '30';
      case BurstCount.frames100:
        return '100';
      case BurstCount.frames300:
        return '300';
    }
  }

  String get aspectLabel {
    switch (aspectRatio) {
      case AspectRatioMode.ratio4x3:
        return '4:3';
      case AspectRatioMode.ratio16x9:
        return '16:9';
      case AspectRatioMode.ratio1x1:
        return '1:1';
    }
  }

  CameraSettings copyWith({
    FlashMode? flashMode,
    TimerDelay? timerDelay,
    BurstCount? burstCount,
    AspectRatioMode? aspectRatio,
    bool? showGrid,
    bool? isFrontCamera,
  }) {
    return CameraSettings(
      flashMode: flashMode ?? this.flashMode,
      timerDelay: timerDelay ?? this.timerDelay,
      burstCount: burstCount ?? this.burstCount,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      showGrid: showGrid ?? this.showGrid,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
    );
  }
}
