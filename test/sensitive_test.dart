import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recoverx/core/sensitive/sensitive_checker.dart';
import 'package:recoverx/data/scan_database.dart';
import 'package:recoverx/domain/file_item.dart';
import 'package:recoverx/domain/sensitive_rating.dart';
import 'package:recoverx/domain/signature_database.dart';

// Model output order: drawings, hentai, neutral, porn, sexy.
const _neutral = [0.05, 0.0, 0.9, 0.03, 0.02];
const _porn = [0.0, 0.05, 0.05, 0.85, 0.05];
const _sexy = [0.0, 0.0, 0.2, 0.1, 0.7];

FileItem _item(String path, {required bool video, int? offset, int size = 4096, String? type}) => FileItem(
      path: path,
      size: size,
      sourceOffset: offset,
      type: FileTypes.byId(type ?? (video ? 'mp4' : 'jpeg'))!,
      matchConfidence: MatchConfidence.high,
    );

Uint8List _rgba(int value) => Uint8List(modelInputSize * modelInputSize * 4)..fillRange(0, modelInputSize * modelInputSize * 4, value);

void main() {
  group('SensitiveRating', () {
    test('levels from model scores', () {
      expect(SensitiveRating.fromOutputs([_neutral])!.level, SensitiveLevel.safe);
      expect(SensitiveRating.fromOutputs([_porn])!.level, SensitiveLevel.explicit);
      expect(SensitiveRating.fromOutputs([_sexy])!.level, SensitiveLevel.suggestive);
      expect(SensitiveRating.fromOutputs([_porn])!.explicit, closeTo(0.9, 1e-9));
    });

    test('a video takes the highest score over its frames', () {
      final r = SensitiveRating.fromOutputs([_neutral, _neutral, _porn, _neutral])!;
      expect(r.level, SensitiveLevel.explicit);
      expect(r.frames, 4);
    });

    test('no usable output gives null', () {
      expect(SensitiveRating.fromOutputs([]), isNull);
      expect(SensitiveRating.fromOutputs([[0.5, 0.5]]), isNull);
    });

    test('encode / decode round trip', () {
      final r = SensitiveRating.fromOutputs([_sexy, _neutral])!;
      expect(SensitiveRating.decode(r.encode()), r);
      expect(SensitiveRating.decode('not json'), isNull);
    });

    test('FileItem carries the rating through toMap (export isolate)', () {
      final item = _item('/a.jpg', video: false)..sensitive = SensitiveRating.fromOutputs([_porn]);
      expect(FileItem.fromMap(item.toMap())!.sensitive, item.sensitive);
    });
  });

  test('RGBA to model input: RGB only, scaled to 0..1', () {
    final rgba = Uint8List(modelInputSize * modelInputSize * 4);
    rgba.setAll(0, [255, 0, 51, 200, 0, 255, 102, 7]);
    final x = rgbaToModelInput(rgba);
    expect(x.length, modelInputSize * modelInputSize * 3);
    expect(x.sublist(0, 6), [1.0, 0.0, closeTo(0.2, 1e-6), 0.0, 1.0, closeTo(0.4, 1e-6)]);
    expect(() => rgbaToModelInput(Uint8List(10)), throwsArgumentError);
  });

  group('SensitiveChecker', () {
    // Pixel value 0 → neutral, 255 → explicit, so tests can tell frames apart.
    final checker = SensitiveChecker(
      classify: (x) async => x[0] > 0.5 ? _porn : _neutral,
      imagePixels: (i) async => i.path.contains('broken') ? null : _rgba(i.path.contains('nsfw') ? 255 : 0),
      videoFrames: (i) async => [_rgba(0), _rgba(255), _rgba(0)],
    );

    test('rates photos and whole-file videos', () async {
      expect((await checker.rate(_item('/ok.jpg', video: false)))!.level, SensitiveLevel.safe);
      expect((await checker.rate(_item('/nsfw.jpg', video: false)))!.level, SensitiveLevel.explicit);
      final v = await checker.rate(_item('/clip.mp4', video: true));
      expect(v!.level, SensitiveLevel.explicit);
      expect(v.frames, 3);
    });

    test('carved photos are checked; carved videos, tiny files and RAW are skipped', () async {
      expect(SensitiveChecker.eligible(_item('/cache.db', video: false, offset: 100)), isTrue);
      expect(SensitiveChecker.eligible(_item('/cache.db', video: true, offset: 100)), isFalse);
      expect(SensitiveChecker.eligible(_item('/icon.png', video: false, size: 100, type: 'png')), isFalse);
      expect(SensitiveChecker.eligible(_item('/raw.dng', video: false, type: 'dng')), isFalse);
      expect(await checker.rate(_item('/cache.db', video: true, offset: 100)), isNull);
    });

    test('undecodable photo gives null', () async {
      expect(await checker.rate(_item('/broken.jpg', video: false)), isNull);
    });
  });

  test('ratings are saved in the scan cache', () async {
    final db = ScanDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final a = _item('/a.jpg', video: false);
    final b = _item('/b.mp4', video: true);
    await db.insertFiles([a, b]);
    final r = SensitiveRating.fromOutputs([_sexy])!;
    await db.saveSensitive({a.id: r});
    final rows = {for (final i in await db.getAllFiles()) i.id: i};
    expect(rows[a.id]!.sensitive, r);
    expect(rows[b.id]!.sensitive, isNull);
  });
}
