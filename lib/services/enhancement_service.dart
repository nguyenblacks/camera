import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/camera_settings.dart';

/// Enhancement pipeline — runs entirely in a Dart isolate via compute().
class EnhancementService {
  /// Main entry point — used by ALL quality levels.
  static Future<Uint8List?> enhanceWithQuality({
    required Uint8List frame1,
    Uint8List? frame2,
    required PictureQuality quality,
    String? deviceModel,
    CameraFilter filter = CameraFilter.none,
  }) async {
    try {
      return await compute(
        _qualityPipeline,
        _QualityParams(
          frame1: frame1,
          frame2: frame2,
          quality: quality,
          deviceModel: deviceModel,
          filter: filter,
        ),
      );
    } catch (e) {
      debugPrint('EnhancementService error: $e');
      return null;
    }
  }

  static Future<Uint8List?> enhanceSingleFrame(Uint8List jpegBytes) =>
      enhanceWithQuality(frame1: jpegBytes, quality: PictureQuality.low);

  static Future<Uint8List?> encodeRgbaToJpeg(
      Uint8List rgba, int width, int height) async {
    return await compute(_encodeRgba, _RgbaParams(rgba, width, height));
  }
}

class _QualityParams {
  final Uint8List frame1;
  final Uint8List? frame2;
  final PictureQuality quality;
  final String? deviceModel;
  final CameraFilter filter;

  _QualityParams({
    required this.frame1,
    this.frame2,
    required this.quality,
    this.deviceModel,
    this.filter = CameraFilter.none,
  });
}

class _RgbaParams {
  final Uint8List rgba;
  final int width, height;
  _RgbaParams(this.rgba, this.width, this.height);
}

Uint8List? _qualityPipeline(_QualityParams p) {
  final dec1 = img.decodeJpg(p.frame1);
  if (dec1 == null) return null;
  img.Image base = img.bakeOrientation(dec1);

  if (p.frame2 != null) {
    final dec2 = img.decodeJpg(p.frame2!);
    if (dec2 != null) {
      final baked2 = img.bakeOrientation(dec2);
      base = _averageFrames(base, baked2);
    }
  }

  // 1. Core quality enhancement
  base = _applyQualityEnhancement(base, p.quality);

  // 2. Photo filter application
  base = _applyPhotoFilter(base, p.filter);

  // 3. Optional watermark
  if (p.deviceModel != null && p.deviceModel!.isNotEmpty) {
    base = _drawWatermark(base, p.deviceModel!);
  }

  final jpegQuality = _jpegQuality(p.quality);
  return Uint8List.fromList(img.encodeJpg(base, quality: jpegQuality));
}

img.Image _averageFrames(img.Image a, img.Image b) {
  final int w = a.width;
  final int h = a.height;
  final out = img.Image(width: w, height: h);

  final bSrc = (b.width == w && b.height == h)
      ? b
      : img.copyResize(b, width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pa = a.getPixel(x, y);
      final pb = bSrc.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        ((pa.r + pb.r) / 2).round().clamp(0, 255),
        ((pa.g + pb.g) / 2).round().clamp(0, 255),
        ((pa.b + pb.b) / 2).round().clamp(0, 255),
      );
    }
  }
  return out;
}

img.Image _applyQualityEnhancement(img.Image src, PictureQuality q) {
  switch (q) {
    case PictureQuality.low:
      return _applyWarmth(src, red: 1.020, green: 1.005, blue: 0.990);

    case PictureQuality.medium:
      var out = _applyWarmth(src, red: 1.045, green: 1.010, blue: 0.970);
      out = _unsharpMask(out, radius: 2, amount: 0.8);
      return out;

    case PictureQuality.high:
      var out = _applyWarmth(src, red: 1.045, green: 1.010, blue: 0.970);
      out = _unsharpMask(out, radius: 2, amount: 1.4);
      out = _autoLevels(out);
      return out;

    case PictureQuality.veryHigh:
      var out = _applyWarmth(src, red: 1.050, green: 1.010, blue: 0.965);
      out = _unsharpMask(out, radius: 1, amount: 1.6);
      out = _unsharpMask(out, radius: 3, amount: 1.0);
      out = _autoLevels(out);
      return out;

    case PictureQuality.ultraHigh:
      var out = _applyWarmth(src, red: 1.050, green: 1.010, blue: 0.965);
      out = _unsharpMask(out, radius: 1, amount: 1.8);
      out = _unsharpMask(out, radius: 3, amount: 1.2);
      out = _unsharpMask(out, radius: 6, amount: 0.6);
      out = _autoLevels(out);
      out = _localContrastBoost(out);
      return out;
  }
}

// ── Photo Filters ─────────────────────────────────────────────────────────────

img.Image _applyPhotoFilter(img.Image src, CameraFilter filter) {
  switch (filter) {
    case CameraFilter.none:
      return src;
    case CameraFilter.warm:
      return _applyWarmth(src, red: 1.12, green: 1.04, blue: 0.90);
    case CameraFilter.cool:
      return _applyWarmth(src, red: 0.90, green: 1.02, blue: 1.15);
    case CameraFilter.vivid:
      return img.adjustColor(src, saturation: 1.45, contrast: 1.20);
    case CameraFilter.noir:
      return img.grayscale(src);
    case CameraFilter.sepia:
      return img.sepia(src);
    case CameraFilter.dramatic:
      var out = img.adjustColor(src, contrast: 1.35, saturation: 0.85);
      return img.vignette(out, start: 0.4, end: 0.95);
    case CameraFilter.cyber:
      return _applyCyber(src);
    case CameraFilter.fade:
      return img.adjustColor(src, contrast: 0.85, brightness: 1.08, saturation: 0.88);
  }
}

img.Image _applyCyber(img.Image src) {
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      // Cyber effect: Boost Cyan (G+B) in shadows, Magenta (R+B) in highlights
      final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
      double r = p.r.toDouble();
      double g = p.g.toDouble();
      double b = p.b.toDouble();

      if (lum < 0.5) {
        // Shadow teal tint
        g = (g * 1.15).clamp(0, 255);
        b = (b * 1.25).clamp(0, 255);
      } else {
        // Highlight pink/purple tint
        r = (r * 1.20).clamp(0, 255);
        b = (b * 1.15).clamp(0, 255);
      }

      out.setPixelRgb(x, y, r.round().clamp(0, 255), g.round().clamp(0, 255), b.round().clamp(0, 255));
    }
  }
  return out;
}

img.Image _applyWarmth(
  img.Image src, {
  required double red,
  required double green,
  required double blue,
}) {
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        (p.r * red).round().clamp(0, 255),
        (p.g * green).round().clamp(0, 255),
        (p.b * blue).round().clamp(0, 255),
      );
    }
  }
  return out;
}

img.Image _unsharpMask(img.Image src, {required int radius, required double amount}) {
  final blurred = img.gaussianBlur(src, radius: radius);
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final orig = src.getPixel(x, y);
      final blur = blurred.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        (orig.r + amount * (orig.r - blur.r)).round().clamp(0, 255),
        (orig.g + amount * (orig.g - blur.g)).round().clamp(0, 255),
        (orig.b + amount * (orig.b - blur.b)).round().clamp(0, 255),
      );
    }
  }
  return out;
}

img.Image _autoLevels(img.Image src) {
  int minR = 255, maxR = 0;
  int minG = 255, maxG = 0;
  int minB = 255, maxB = 0;

  for (final p in src) {
    if (p.r < minR) minR = p.r.toInt();
    if (p.r > maxR) maxR = p.r.toInt();
    if (p.g < minG) minG = p.g.toInt();
    if (p.g > maxG) maxG = p.g.toInt();
    if (p.b < minB) minB = p.b.toInt();
    if (p.b > maxB) maxB = p.b.toInt();
  }

  final rng = (v) => v.clamp(1, 255);
  final rangeR = rng(maxR - minR);
  final rangeG = rng(maxG - minG);
  final rangeB = rng(maxB - minB);

  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        (((p.r.toInt() - minR) / rangeR) * 255).round().clamp(0, 255),
        (((p.g.toInt() - minG) / rangeG) * 255).round().clamp(0, 255),
        (((p.b.toInt() - minB) / rangeB) * 255).round().clamp(0, 255),
      );
    }
  }
  return out;
}

img.Image _localContrastBoost(img.Image src) {
  final blurred = img.gaussianBlur(src, radius: 12);
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final o = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);
      out.setPixelRgb(
        x,
        y,
        (o.r + 0.30 * (o.r - b.r)).round().clamp(0, 255),
        (o.g + 0.30 * (o.g - b.g)).round().clamp(0, 255),
        (o.b + 0.30 * (o.b - b.b)).round().clamp(0, 255),
      );
    }
  }
  return out;
}

img.Image _drawWatermark(img.Image src, String deviceModel) {
  final now = DateTime.now();
  final ts = '${now.year}-${now.month.toString().padLeft(2,'0')}-'
      '${now.day.toString().padLeft(2,'0')} '
      '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
  final text = '$deviceModel  $ts';

  img.drawString(
    src,
    text,
    font: img.arial14,
    x: src.width - (text.length * 8) - 14,
    y: src.height - 28,
    color: img.ColorRgb8(0, 0, 0),
  );
  img.drawString(
    src,
    text,
    font: img.arial14,
    x: src.width - (text.length * 8) - 16,
    y: src.height - 30,
    color: img.ColorRgb8(255, 255, 255),
  );
  return src;
}

int _jpegQuality(PictureQuality q) {
  switch (q) {
    case PictureQuality.low:
      return 90;
    case PictureQuality.medium:
      return 93;
    case PictureQuality.high:
      return 95;
    case PictureQuality.veryHigh:
      return 96;
    case PictureQuality.ultraHigh:
      return 97;
  }
}

Uint8List? _encodeRgba(_RgbaParams p) {
  final image = img.Image(width: p.width, height: p.height);
  for (int row = 0; row < p.height; row++) {
    for (int col = 0; col < p.width; col++) {
      final int idx = (row * p.width + col) * 4;
      image.setPixelRgb(col, row, p.rgba[idx], p.rgba[idx + 1], p.rgba[idx + 2]);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
