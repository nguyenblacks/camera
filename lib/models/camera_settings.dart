import 'package:camera/camera.dart';

enum CameraMode { photo, video }

enum PictureQuality { low, medium, high, veryHigh, ultraHigh }

enum TimerDelay { off, three, ten }

enum AspectRatioMode { ratio4x3, ratio16x9, ratio1x1, full }

enum AntiBandingMode { auto, hz50, hz60, off }

enum VideoQuality { hd, fhd, uhd }

enum CaptureMethod { normal, palm, voice }

enum CameraFilter { none, warm, cool, vivid, noir, sepia, dramatic, cyber, fade }

extension CameraFilterExtension on CameraFilter {
  String get label {
    switch (this) {
      case CameraFilter.none:
        return 'Original';
      case CameraFilter.warm:
        return 'Warm';
      case CameraFilter.cool:
        return 'Cool';
      case CameraFilter.vivid:
        return 'Vivid';
      case CameraFilter.noir:
        return 'B&W';
      case CameraFilter.sepia:
        return 'Vintage';
      case CameraFilter.dramatic:
        return 'Dramatic';
      case CameraFilter.cyber:
        return 'Cyber';
      case CameraFilter.fade:
        return 'Film';
    }
  }
}

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
  bool watermarkEnabled;
  String? selectedSoundPath;
  VideoQuality videoQuality;
  CaptureMethod captureMethod;
  CameraFilter filter;

  CameraSettings({
    this.cameraMode = CameraMode.photo,
    this.flashMode = FlashMode.off,
    this.timerDelay = TimerDelay.off,
    this.quality = PictureQuality.medium,
    this.aspectRatio = AspectRatioMode.ratio4x3,
    this.antiBanding = AntiBandingMode.auto,
    this.enableShutterSound = true,
    this.showGrid = false,
    this.isFrontCamera = false,
    this.watermarkEnabled = false,
    this.selectedSoundPath,
    this.videoQuality = VideoQuality.fhd,
    this.captureMethod = CaptureMethod.normal,
    this.filter = CameraFilter.none,
  });

  bool get usesTwoFrames => quality != PictureQuality.low;

  String get qualityLabel {
    switch (quality) {
      case PictureQuality.low:
        return 'Low (1 shot, instant)';
      case PictureQuality.medium:
        return 'Standard (2-shot blend)';
      case PictureQuality.high:
        return 'High (2-shot + sharp)';
      case PictureQuality.veryHigh:
        return 'Very High (2-shot + deep process)';
      case PictureQuality.ultraHigh:
        return 'Ultra (2-shot + max enhance)';
    }
  }

  String get qualityShortLabel {
    switch (quality) {
      case PictureQuality.low:
        return 'Low';
      case PictureQuality.medium:
        return 'Standard';
      case PictureQuality.high:
        return 'High';
      case PictureQuality.veryHigh:
        return 'V.High';
      case PictureQuality.ultraHigh:
        return 'Ultra';
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

  String get videoQualityLabel {
    switch (videoQuality) {
      case VideoQuality.hd:
        return 'HD (720p)';
      case VideoQuality.fhd:
        return 'Full HD (1080p)';
      case VideoQuality.uhd:
        return '4K (2160p)';
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
    bool? watermarkEnabled,
    String? selectedSoundPath,
    VideoQuality? videoQuality,
    CaptureMethod? captureMethod,
    CameraFilter? filter,
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
      watermarkEnabled: watermarkEnabled ?? this.watermarkEnabled,
      selectedSoundPath: selectedSoundPath ?? this.selectedSoundPath,
      videoQuality: videoQuality ?? this.videoQuality,
      captureMethod: captureMethod ?? this.captureMethod,
      filter: filter ?? this.filter,
    );
  }
}
