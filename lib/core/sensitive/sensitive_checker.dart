import 'dart:typed_data';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';
import '../../domain/sensitive_rating.dart';

/// Model input side length (MobileNetV2 224).
const modelInputSize = 224;

/// Runs the model on one `1×224×224×3` float input; returns its 5 scores in
/// [SensitiveRating.labels] order.
typedef ClassifyFn = Future<List<double>> Function(Float32List input);

/// RGBA pixels of a photo, resized to [modelInputSize]². Null if it can't
/// be decoded.
typedef ImagePixelsFn = Future<Uint8List?> Function(FileItem item);

/// RGBA pixels of a few frames of a video, each [modelInputSize]².
typedef VideoFramesFn = Future<List<Uint8List>> Function(FileItem item);

/// Turns RGBA bytes (`size × size × 4`) into the model's float RGB input,
/// scaled to 0..1 (the model was trained on `pixels / 255`).
Float32List rgbaToModelInput(Uint8List rgba, {int size = modelInputSize}) {
  final n = size * size;
  if (rgba.length < n * 4) {
    throw ArgumentError('Expected ${n * 4} RGBA bytes, got ${rgba.length}');
  }
  final out = Float32List(n * 3);
  for (var i = 0, o = 0, p = 0; i < n; i++, p += 4) {
    out[o++] = rgba[p] / 255.0;
    out[o++] = rgba[p + 1] / 255.0;
    out[o++] = rgba[p + 2] / 255.0;
  }
  return out;
}

/// Rates photos and videos for sensitive content, read-only and in memory.
///
/// * Photos (including carved ones) are decoded to 224×224 in memory.
/// * Whole-file videos: a few frames spread over the video; the highest
///   scores count. Carved videos are skipped (the frame grabber needs a file
///   of its own, which would mean writing to the device).
class SensitiveChecker {
  const SensitiveChecker({required this.classify, required this.imagePixels, required this.videoFrames});

  final ClassifyFn classify;
  final ImagePixelsFn imagePixels;
  final VideoFramesFn videoFrames;

  /// Image types the platform decoder can read.
  static const imageTypes = {'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif'};

  /// Smaller files are icons / broken fragments, not worth a model run.
  static const minBytes = 512;

  /// Photos are read into memory to decode; skip anything larger.
  static const maxImageBytes = 48 * 1024 * 1024;

  static bool eligible(FileItem i) {
    if (i.size < minBytes) return false;
    if (i.category == FileCategory.image) {
      return imageTypes.contains(i.type.id) && i.size <= maxImageBytes;
    }
    return i.category == FileCategory.video && !i.isCarved;
  }

  /// Null when the item is not eligible or nothing could be decoded.
  Future<SensitiveRating?> rate(FileItem item) async {
    if (!eligible(item)) return null;
    final List<Uint8List> frames;
    if (item.category == FileCategory.video) {
      frames = await videoFrames(item);
    } else {
      final pixels = await imagePixels(item);
      frames = pixels == null ? const [] : [pixels];
    }
    final outputs = <List<double>>[];
    for (final f in frames) {
      outputs.add(await classify(rgbaToModelInput(f)));
    }
    return SensitiveRating.fromOutputs(outputs);
  }
}
