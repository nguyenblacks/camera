import 'package:camera/camera.dart';

enum CameraMode { photo, video }

enum PictureQuality { low, medium, high, veryHigh, ultraHigh }

enum TimerDelay { off, three, ten }

enum AspectRatioMode { ratio4x3, ratio16x9, ratio1x1, full }

enum AntiBandingMode { auto, hz50, hz60, off }

class CameraSettings {
  CameraMode cameraMode;
  FlashMode flashMode;
  TimerDelay timerDelay;
  PictureQuality quality;
  AspectRatioMode aspectRatio;
  AntiBandingMode antiBanding;
  bool enableShutterSound;
  bool showGrid;
  bool isFrontCamera;

  CameraSettings({
    this.cameraMode = CameraMode.photo,
    this.flashMode = FlashMode.off,
    this.timerDelay = TimerDelay.off,
    this.quality = PictureQuality.medium, // Medium (10 frames) default for fast, crisp results
    this.aspectRatio = AspectRatioMode.ratio4x3, // Default 4:3
    this.antiBanding = AntiBandingMode.auto,
    this.enableShutterSound = true,
    this.showGrid = false,
    this.isFrontCamera = false,
  });

  int get frameCount {
    switch (quality) {
      case PictureQuality.low:
        return 1;
      case PictureQuality.medium:
        return 10;
      case PictureQuality.high:
        return 20;
      case PictureQuality.veryHigh:
        return 50;
      case PictureQuality.ultraHigh:
        return 100;
    }
  }

  String get qualityLabel {
    switch (quality) {
      case PictureQuality.low:
        return 'Low (1 Frame Instant)';
      case PictureQuality.medium:
        return 'Medium (10 Frames)';
      case PictureQuality.high:
        return 'High (20 Frames)';
      case PictureQuality.veryHigh:
        return 'Very High (50 Frames)';
      case PictureQuality.ultraHigh:
        return 'Ultra High (100 Frames)';
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

  double? get aspectRatioRatio {
    switch (aspectRatio) {
      case AspectRatioMode.ratio4x3:
        return 3.0 / 4.0;
      case AspectRatioMode.ratio16x9:
        return 9.0 / 16.0;
      case AspectRatioMode.ratio1x1:
        return 1.0;
      case AspectRatioMode.full:
        return null;
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

  String get aspectLabel {
    switch (aspectRatio) {
      case AspectRatioMode.ratio4x3:
        return '4:3';
      case AspectRatioMode.ratio16x9:
        return '16:9';
      case AspectRatioMode.ratio1x1:
        return '1:1';
      case AspectRatioMode.full:
        return 'Full';
    }
  }

  String get antiBandingLabel {
    switch (antiBanding) {
      case AntiBandingMode.auto:
        return 'Auto';
      case AntiBandingMode.hz50:
        return '50Hz';
      case AntiBandingMode.hz60:
        return '60Hz';
      case AntiBandingMode.off:
        return 'Off';
    }
  }

  CameraSettings copyWith({
    CameraMode? cameraMode,
    FlashMode? flashMode,
    TimerDelay? timerDelay,
    PictureQuality? quality,
    AspectRatioMode? aspectRatio,
    AntiBandingMode? antiBanding,
    bool? enableShutterSound,
    bool? showGrid,
    bool? isFrontCamera,
  }) {
    return CameraSettings(
      cameraMode: cameraMode ?? this.cameraMode,
      flashMode: flashMode ?? this.flashMode,
      timerDelay: timerDelay ?? this.timerDelay,
      quality: quality ?? this.quality,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      antiBanding: antiBanding ?? this.antiBanding,
      enableShutterSound: enableShutterSound ?? this.enableShutterSound,
      showGrid: showGrid ?? this.showGrid,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
    );
  }
}
