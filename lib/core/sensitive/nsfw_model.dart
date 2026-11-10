import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../domain/file_item.dart';
import '../../domain/sensitive_rating.dart';
import 'sensitive_checker.dart';

/// On-device NSFW classifier (`assets/models/nsfw_mobilenet_v2_224.tflite`,
/// see `assets/models/README.md`). Inference runs in its own isolate.
class NsfwModel {
  NsfwModel._(this._interpreter, this._isolate);

  static const asset = 'assets/models/nsfw_mobilenet_v2_224.tflite';

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  static Future<NsfwModel> load() async {
    final interpreter = await Interpreter.fromAsset(asset, options: InterpreterOptions()..threads = 4);
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    if (input.length != 4 || input[1] != modelInputSize || input[2] != modelInputSize || input[3] != 3 ||
        output.last != SensitiveRating.labels.length) {
      interpreter.close();
      throw StateError('Unexpected model shape: in $input, out $output');
    }
    final isolate = await IsolateInterpreter.create(address: interpreter.address);
    return NsfwModel._(interpreter, isolate);
  }

  /// Scores for one input, in [SensitiveRating.labels] order.
  Future<List<double>> classify(Float32List input) async {
    final out = Float32List(SensitiveRating.labels.length);
    await _isolate.run(input.buffer, out.buffer);
    return out.toList();
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

/// Reads an item's bytes (the carved range for carved items) into memory.
/// Read-only; nothing is written.
Future<Uint8List> readItemBytesForCheck(FileItem item) async {
  final raf = await File(item.path).open();
  try {
    await raf.setPosition(item.sourceOffset ?? 0);
    return await raf.read(item.size);
  } finally {
    await raf.close();
  }
}

/// Decodes a photo in memory straight to [modelInputSize]² RGBA.
Future<Uint8List?> decodeImagePixels(FileItem item) async {
  try {
    final bytes = await readItemBytesForCheck(item);
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: modelInputSize, targetHeight: modelInputSize);
    try {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      return data?.buffer.asUint8List();
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Grabs [count] frames spread over a video with Android's
/// `MediaMetadataRetriever` (see `VideoFrames.kt`), scaled to
/// [modelInputSize]² RGBA, in memory. The file is only read.
Future<List<Uint8List>> sampleVideoFrames(FileItem item, {int count = 4}) async {
  const channel = MethodChannel('recoverx/media');
  try {
    final frames = await channel.invokeListMethod<Uint8List>('videoFrames', {
      'path': item.path,
      'count': count,
      'size': modelInputSize,
    });
    return frames ?? const [];
  } on PlatformException {
    return const [];
  }
}
