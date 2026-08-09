import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Enhancement pipeline running entirely in a Dart isolate via compute().
/// Steps:
/// 1. Frame averaging (stacking) to eliminate sensor noise.
/// 2. Warmth balance (rich golden/natural skin tones for budget sensors).
/// 3. High-pass super clarity & micro-contrast sharpening (making 8MP look razor sharp).
/// 4. Dynamic contrast auto-levels.
/// 5. Encode JPEG at 95% quality.
class EnhancementService {
  /// Takes raw accumulated [accumulator] (sum of RGB values across N frames),
  /// averages pixels, applies warmth & super clarity enhancement.
  /// Returns JPEG bytes of the final image.
  static Future<Uint8List?> process({
    required Float64List accumulator,
    required int frameCount,
    required int width,
    required int height,
  }) async {
    try {
      return await compute(
        _enhancePipeline,
        _EnhanceParams(
          accumulator: accumulator,
          frameCount: frameCount,
          width: width,
          height: height,
        ),
      );
    } catch (e) {
      debugPrint('EnhancementService error: $e');
      return null;
    }
  }

  /// Enhances a single JPEG (e.g., from native Camera2 ISP capture).
  /// Applies warmth balance + super clarity sharpening + auto-levels in an isolate.
  static Future<Uint8List?> enhanceSingleFrame(Uint8List jpegBytes) async {
    try {
      return await compute(_enhanceSingleJpeg, jpegBytes);
    } catch (e) {
      debugPrint('enhanceSingleFrame error: $e');
      return null;
    }
  }

  /// Encodes a raw RGBA Uint8List to JPEG for thumbnail preview.
  static Future<Uint8List?> encodeRgbaToJpeg(
      Uint8List rgba, int width, int height) async {
    return await compute(_encodeRgba, _RgbaParams(rgba, width, height));
  }
}

// ── Isolate-safe top-level functions ────────────────────────────────────────

class _EnhanceParams {
  final Float64List accumulator;
  final int frameCount, width, height;

  _EnhanceParams({
    required this.accumulator,
    required this.frameCount,
    required this.width,
    required this.height,
  });
}

class _RgbaParams {
  final Uint8List rgba;
  final int width, height;
  _RgbaParams(this.rgba, this.width, this.height);
}

/// Main enhancement pipeline for stacked burst frames (runs in isolate).
Uint8List? _enhancePipeline(_EnhanceParams p) {
  final int n = p.frameCount;
  final int w = p.width;
  final int h = p.height;

  // 1. Build img.Image from the averaged accumulator
  final image = img.Image(width: w, height: h);

  for (int row = 0; row < h; row++) {
    for (int col = 0; col < w; col++) {
      final int idx = (row * w + col) * 3;
      final int r = (p.accumulator[idx] / n).round().clamp(0, 255);
      final int g = (p.accumulator[idx + 1] / n).round().clamp(0, 255);
      final int b = (p.accumulator[idx + 2] / n).round().clamp(0, 255);
      image.setPixelRgb(col, row, r, g, b);
    }
  }

  // 2. Apply Warmth & Super Clarity enhancement
  final enhanced = _applyWarmthAndSuperClarity(image);

  // 3. Auto-levels: stretch contrast for punchy dynamic range
  final leveled = _autoLevels(enhanced);

  // 4. Encode to high quality JPEG
  return Uint8List.fromList(img.encodeJpg(leveled, quality: 95));
}

/// Single JPEG enhancement pipeline (runs in isolate).
Uint8List? _enhanceSingleJpeg(Uint8List jpegBytes) {
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) return null;

  // Bake EXIF orientation so portrait photos are right-side-up and sharp
  final image = img.bakeOrientation(decoded);

  final enhanced = _applyWarmthAndSuperClarity(image);
  final leveled = _autoLevels(enhanced);
  return Uint8List.fromList(img.encodeJpg(leveled, quality: 95));
}

/// Applies Warmth (color temp tuning) and Super Clarity (micro-contrast + multi-radius unsharp mask).
/// Optimized to make budget 8MP camera photos look warm, sharp, and detailed.
img.Image _applyWarmthAndSuperClarity(img.Image src) {
  final w = src.width;
  final h = src.height;

  // ── Step A: Micro-contrast gaussian blur pass ────────────────────────────
  final blurred = img.gaussianBlur(src, radius: 2);

  // ── Step B: Sharpness boost + Warmth color tuning ─────────────────────────
  // Unsharp mask strength: 1.6 for crisp detail boost on 8MP sensors
  const double sharpAmount = 1.6;

  // Warmth factors:
  // Red +4.5% boost (warmth / rich tones)
  // Green +1.0% boost (natural skin/foliage preservation)
  // Blue -3.0% shift (removes cold digital blue haze)
  const double redWarmth = 1.045;
  const double greenWarmth = 1.010;
  const double blueWarmth = 0.970;

  final out = img.Image(width: w, height: h);

  for (int row = 0; row < h; row++) {
    for (int col = 0; col < w; col++) {
      final orig = src.getPixel(col, row);
      final blur = blurred.getPixel(col, row);

      // Unsharp mask calculation
      double r = orig.r + sharpAmount * (orig.r - blur.r);
      double g = orig.g + sharpAmount * (orig.g - blur.g);
      double b = orig.b + sharpAmount * (orig.b - blur.b);

      // Warmth color tuning
      r *= redWarmth;
      g *= greenWarmth;
      b *= blueWarmth;

      out.setPixelRgb(
        col,
        row,
        r.round().clamp(0, 255),
        g.round().clamp(0, 255),
        b.round().clamp(0, 255),
      );
    }
  }

  return out;
}

/// Auto-levels: stretch dynamic range to [0, 255].
img.Image _autoLevels(img.Image src) {
  int minR = 255, maxR = 0;
  int minG = 255, maxG = 0;
  int minB = 255, maxB = 0;

  for (final pixel in src) {
    if (pixel.r < minR) minR = pixel.r.toInt();
    if (pixel.r > maxR) maxR = pixel.r.toInt();
    if (pixel.g < minG) minG = pixel.g.toInt();
    if (pixel.g > maxG) maxG = pixel.g.toInt();
    if (pixel.b < minB) minB = pixel.b.toInt();
    if (pixel.b > maxB) maxB = pixel.b.toInt();
  }

  final rangeR = (maxR - minR).clamp(1, 255);
  final rangeG = (maxG - minG).clamp(1, 255);
  final rangeB = (maxB - minB).clamp(1, 255);

  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = (((p.r.toInt() - minR) / rangeR) * 255).round().clamp(0, 255);
      final g = (((p.g.toInt() - minG) / rangeG) * 255).round().clamp(0, 255);
      final b = (((p.b.toInt() - minB) / rangeB) * 255).round().clamp(0, 255);
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

/// Encode raw RGBA bytes to JPEG (runs in isolate).
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
