import 'package:camera/camera.dart';
import 'package:color_filter_extension/color_filter_extension.dart';

enum CameraMode { photo, portrait, video, night, timelapse }

enum PictureQuality { low, medium, high, veryHigh, ultraHigh }

enum TimerDelay { off, three, ten }

enum AspectRatioMode { ratio4x3, ratio16x9, ratio1x1, full }

enum AntiBandingMode { auto, hz50, hz60, off }

enum VideoQuality { hd, fhd, uhd }

enum CaptureMethod { normal, voice }

enum HdrMode { auto, on, off }

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
  int timelapseIntervalSeconds;
  HdrMode hdrMode;
  bool saveLocationInfo;
  double bokehBlurLevel; // 0.0 (no blur) to 1.0 (max blur f/1.4)
  String bokehFStop;     // 'f/1.4', 'f/2.0', 'f/2.8', 'f/4.0', 'f/8.0'
  ColorFiltersPreset? activeFilter;
  int timelapseDurationSeconds;

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
    this.timelapseIntervalSeconds = 2,
    this.hdrMode = HdrMode.auto,
    this.saveLocationInfo = false,
    this.bokehBlurLevel = 0.6,
    this.bokehFStop = 'f/2.8',
    this.activeFilter,
    this.timelapseDurationSeconds = 0, // 0 = infinite
  });

  bool get usesTwoFrames => false;

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

  String get hdrLabel {
    switch (hdrMode) {
      case HdrMode.auto:
        return 'HDR Auto';
      case HdrMode.on:
        return 'HDR On';
      case HdrMode.off:
        return 'HDR Off';
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
    int? timelapseIntervalSeconds,
    HdrMode? hdrMode,
    bool? saveLocationInfo,
    double? bokehBlurLevel,
    String? bokehFStop,
    ColorFiltersPreset? activeFilter,
    int? timelapseDurationSeconds,
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
      timelapseIntervalSeconds:
          timelapseIntervalSeconds ?? this.timelapseIntervalSeconds,
      hdrMode: hdrMode ?? this.hdrMode,
      saveLocationInfo: saveLocationInfo ?? this.saveLocationInfo,
      bokehBlurLevel: bokehBlurLevel ?? this.bokehBlurLevel,
      bokehFStop: bokehFStop ?? this.bokehFStop,
      activeFilter: activeFilter ?? this.activeFilter,
      timelapseDurationSeconds: timelapseDurationSeconds ?? this.timelapseDurationSeconds,
    );
  }
}
