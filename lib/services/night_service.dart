import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Low-light computational photography service for NIGHT mode.
///
/// Motion-Adaptive Temporal Denoising:
/// 1. Uses Frame 1 as sharp structural anchor reference.
/// 2. Motion-adaptive pixel blending: averages dark flat areas across 4 frames for 50% noise reduction,
///    while relying on the reference frame for moving/shaking edges — preventing any motion blur, ghosting, or mush!
/// 3. Low-Light Shadow Lift & Tone Curve: gracefully brightens dark shadows while retaining highlights.
class NightService {
  static Future<Uint8List?> processNightSight({
    required List<Uint8List> frames,
    String? deviceModel,
  }) async {
    try {
      return await compute(
        _nightPipeline,
        _NightParams(frames: frames, deviceModel: deviceModel),
      );
    } catch (e) {
      debugPrint('NightService error: $e');
      return null;
    }
  }
}

class _NightParams {
  final List<Uint8List> frames;
  final String? deviceModel;

  _NightParams({required this.frames, this.deviceModel});
}

Uint8List? _nightPipeline(_NightParams p) {
  if (p.frames.isEmpty) return null;

  // 1. Decode & bake orientation of anchor frame 1
  final dec1 = img.decodeJpg(p.frames[0]);
  if (dec1 == null) return null;
  img.Image ref = img.bakeOrientation(dec1);

  // 2. Motion-adaptive multi-frame blending (prevents mush & ghosting)
  if (p.frames.length > 1) {
    final List<img.Image> candidateFrames = [];
    for (int i = 1; i < p.frames.length; i++) {
      final dec = img.decodeJpg(p.frames[i]);
      if (dec != null) {
        candidateFrames.add(img.bakeOrientation(dec));
      }
    }
    if (candidateFrames.isNotEmpty) {
      ref = _motionAdaptiveBlend(ref, candidateFrames);
    }
  }

  // 3. Low-Light Shadow Lift + Tone Curve
  ref = _applyNightToneCurve(ref);

  // 4. Denoised edge sharpening
  ref = _nightThresholdSharpen(ref);

  // 5. Optional watermark
  if (p.deviceModel != null && p.deviceModel!.isNotEmpty) {
    ref = _drawNightWatermark(ref, p.deviceModel!);
  }

  return Uint8List.fromList(img.encodeJpg(ref, quality: 97));
}

/// Motion-adaptive temporal blend:
/// High-contrast moving pixels use reference frame (zero blur/mush).
/// Low-contrast static pixels average all frames (50% noise reduction).
img.Image _motionAdaptiveBlend(img.Image ref, List<img.Image> candidates) {
  final int w = ref.width;
  final int h = ref.height;
  final out = img.Image(width: w, height: h);

  final List<img.Image> resizedCandidates = candidates.map((c) {
    return (c.width == w && c.height == h)
        ? c
        : img.copyResize(c, width: w, height: h);
  }).toList();

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pRef = ref.getPixel(x, y);

      double sumR = pRef.r.toDouble();
      double sumG = pRef.g.toDouble();
      double sumB = pRef.b.toDouble();
      double totalWeight = 1.0;

      for (int i = 0; i < resizedCandidates.length; i++) {
        final pCand = resizedCandidates[i].getPixel(x, y);

        final diffR = (pCand.r - pRef.r).abs();
        final diffG = (pCand.g - pRef.g).abs();
        final diffB = (pCand.b - pRef.b).abs();
        final maxDiff = diffR > diffG ? (diffR > diffB ? diffR : diffB) : (diffG > diffB ? diffG : diffB);

        // Motion thresholding: static flat pixels get weight=1.0; moving edge pixels get weight=0
        double weight = 1.0;
        if (maxDiff > 16) {
          weight = (1.0 - (maxDiff - 16) / 32.0).clamp(0.0, 1.0);
        }

        sumR += pCand.r * weight;
        sumG += pCand.g * weight;
        sumB += pCand.b * weight;
        totalWeight += weight;
      }

      out.setPixelRgb(
        x,
        y,
        (sumR / totalWeight).round().clamp(0, 255),
        (sumG / totalWeight).round().clamp(0, 255),
        (sumB / totalWeight).round().clamp(0, 255),
      );
    }
  }
  return out;
}

/// Low-light tone curve: lifts dark shadows using gamma transform while preserving bright lights
img.Image _applyNightToneCurve(img.Image src) {
  final out = img.Image(width: src.width, height: src.height);

  final lut = List<int>.generate(256, (i) {
    final double norm = i / 255.0;
    final double lifted = (norm <= 0)
        ? 0.0
        : (1.08 * (norm < 0.5 ? math.pow(norm, 0.74) : math.pow(norm, 0.88)));
    return (lifted * 255.0).round().clamp(0, 255);
  });

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = (lut[p.r.toInt()] * 1.03).round().clamp(0, 255);
      final g = lut[p.g.toInt()];
      final b = (lut[p.b.toInt()] * 0.98).round().clamp(0, 255);

      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

/// Denoised edge sharpening for night photos
img.Image _nightThresholdSharpen(img.Image src) {
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

      if (maxDiff > 9) {
        out.setPixelRgb(
          x,
          y,
          (orig.r + 0.45 * (orig.r - blur.r)).round().clamp(0, 255),
          (orig.g + 0.45 * (orig.g - blur.g)).round().clamp(0, 255),
          (orig.b + 0.45 * (orig.b - blur.b)).round().clamp(0, 255),
        );
      } else {
        out.setPixelRgb(x, y, orig.r.toInt(), orig.g.toInt(), orig.b.toInt());
      }
    }
  }
  return out;
}

img.Image _drawNightWatermark(img.Image src, String deviceModel) {
  final now = DateTime.now();
  final ts = '${now.year}-${now.month.toString().padLeft(2,'0')}-'
      '${now.day.toString().padLeft(2,'0')} '
      '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
  final text = '$deviceModel Night Sight  $ts';

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
