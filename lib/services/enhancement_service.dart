import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/camera_settings.dart';

/// Enhancement pipeline — runs entirely in a Dart isolate via compute().
///
/// Fix for noise/mush:
///  • No aggressive auto-levels or multi-pass unsharp masks (which amplify noise & halos).
///  • Threshold-masked edge sharpening: only sharpens distinct edges, leaving flat areas
///    (skin, sky, shadows) smooth and noise-free.
///  • Natural color warmth tuning.
class EnhancementService {
  static Future<Uint8List?> enhanceWithQuality({
    required Uint8List frame1,
    Uint8List? frame2,
    required PictureQuality quality,
    String? deviceModel,
    List<double>? filterMatrix,
  }) async {
    try {
      return await compute(
        _qualityPipeline,
        _QualityParams(
          frame1: frame1,
          frame2: frame2,
          quality: quality,
          deviceModel: deviceModel,
          filterMatrix: filterMatrix,
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
  final List<double>? filterMatrix;

  _QualityParams({
    required this.frame1,
    this.frame2,
    required this.quality,
    this.deviceModel,
    this.filterMatrix,
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

  // 1. Pixel-average 2 hardware ISP frames to cut sensor noise by ~30%
  if (p.frame2 != null) {
    final dec2 = img.decodeJpg(p.frame2!);
    if (dec2 != null) {
      final baked2 = img.bakeOrientation(dec2);
      base = _averageFrames(base, baked2);
    }
  }

  // 2. Clean, natural enhancement (denoised edge sharpening + warm balance)
  base = _applyNaturalEnhancement(base, p.quality);

  // 3. Apply custom color matrix filter if selected
  if (p.filterMatrix != null && p.filterMatrix!.length == 20) {
    base = _applyColorMatrix(base, p.filterMatrix!);
  }

  // 4. Optional device watermark
  if (p.deviceModel != null && p.deviceModel!.isNotEmpty) {
    base = _drawWatermark(base, p.deviceModel!);
  }

  final jpegQuality = _jpegQuality(p.quality);
  return Uint8List.fromList(img.encodeJpg(base, quality: jpegQuality));
}

/// Averages 2 frames to reduce hardware sensor noise
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

/// Applies subtle color warmth + threshold-masked edge sharpening.
img.Image _applyNaturalEnhancement(img.Image src, PictureQuality q) {
  switch (q) {
    case PictureQuality.low:
      // Single frame: mild warmth boost only
      return _applyWarmth(src, red: 1.020, green: 1.005, blue: 0.990);

    case PictureQuality.medium:
      // Standard: warmth + subtle edge sharpening (amount 0.35, threshold 8)
      var out = _applyWarmth(src, red: 1.035, green: 1.008, blue: 0.975);
      out = _thresholdUnsharpMask(out, amount: 0.35, threshold: 8);
      return out;

    case PictureQuality.high:
      // High: warmth + medium edge sharpening (amount 0.45, threshold 7)
      var out = _applyWarmth(src, red: 1.040, green: 1.010, blue: 0.970);
      out = _thresholdUnsharpMask(out, amount: 0.45, threshold: 7);
      return out;

    case PictureQuality.veryHigh:
      // Very High: warmth + refined edge sharpening (amount 0.55, threshold 6)
      var out = _applyWarmth(src, red: 1.042, green: 1.010, blue: 0.968);
      out = _thresholdUnsharpMask(out, amount: 0.55, threshold: 6);
      return out;

    case PictureQuality.ultraHigh:
      // Ultra: rich warmth + crisp edge sharpening (amount 0.65, threshold 5)
      var out = _applyWarmth(src, red: 1.045, green: 1.010, blue: 0.965);
      out = _thresholdUnsharpMask(out, amount: 0.65, threshold: 5);
      return out;
  }
}

/// Threshold-masked unsharp mask:
/// Only sharpens pixels where high-frequency detail exceeds [threshold].
/// Leaves flat areas (skin, sky, background shadows) smooth without amplifying noise.
img.Image _thresholdUnsharpMask(img.Image src, {required double amount, required int threshold}) {
  final blurred = img.gaussianBlur(src, radius: 1);
  final out = img.Image(width: src.width, height: src.height);

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final orig = src.getPixel(x, y);
      final blur = blurred.getPixel(x, y);

      final diffR = (orig.r - blur.r).abs();
      final diffG = (orig.g - blur.g).abs();
      final diffB = (orig.b - blur.b).abs();
      final maxDiff = diffR > diffG ? (diffR > diffB ? diffR : diffB) : (diffG > diffB ? diffG : diffB);

      if (maxDiff > threshold) {
        // High-contrast edge detected — apply gentle sharpening
        out.setPixelRgb(
          x,
          y,
          (orig.r + amount * (orig.r - blur.r)).round().clamp(0, 255),
          (orig.g + amount * (orig.g - blur.g)).round().clamp(0, 255),
          (orig.b + amount * (orig.b - blur.b)).round().clamp(0, 255),
        );
      } else {
        // Flat noise region — keep original pixel untouched
        out.setPixelRgb(x, y, orig.r.toInt(), orig.g.toInt(), orig.b.toInt());
      }
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
      return 92;
    case PictureQuality.medium:
      return 94;
    case PictureQuality.high:
      return 96;
    case PictureQuality.veryHigh:
      return 97;
    case PictureQuality.ultraHigh:
      return 98;
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

/// Applies a 5x4 color matrix (standard Flutter ColorMatrix) to the image
img.Image _applyColorMatrix(img.Image src, List<double> matrix) {
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = p.r;
      final g = p.g;
      final b = p.b;
      // matrix is 20 elements. 
      // row 1: R
      final newR = r * matrix[0] + g * matrix[1] + b * matrix[2] + 255 * matrix[3] + matrix[4];
      // row 2: G
      final newG = r * matrix[5] + g * matrix[6] + b * matrix[7] + 255 * matrix[8] + matrix[9];
      // row 3: B
      final newB = r * matrix[10] + g * matrix[11] + b * matrix[12] + 255 * matrix[13] + matrix[14];
      
      out.setPixelRgb(
        x,
        y,
        newR.round().clamp(0, 255),
        newG.round().clamp(0, 255),
        newB.round().clamp(0, 255),
      );
    }
  }
  return out;
}
