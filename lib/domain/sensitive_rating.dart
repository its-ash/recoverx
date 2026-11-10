import 'dart:convert';
import 'dart:math' as math;

/// Outcome of the on-device sensitive-content check.
enum SensitiveLevel {
  /// Nothing above the thresholds.
  safe,

  /// Revealing / suggestive (the model's `sexy` class).
  suggestive,

  /// Sexually explicit photo or drawing (`porn` + `hentai`).
  explicit,
}

/// Score limits above which an item is flagged.
class SensitiveThresholds {
  const SensitiveThresholds({required this.explicit, required this.suggestive});

  final double explicit;
  final double suggestive;

  /// Explicit + suggestive together: catches items split between classes.
  double get combined => math.min(0.95, (explicit + suggestive) / 2 + 0.15);

  static const balanced = SensitiveThresholds(explicit: 0.6, suggestive: 0.6);

  /// Limits in use, set from Settings (Sensitivity). Ratings store raw
  /// scores, so changing this re-labels every item without re-running the
  /// model.
  static SensitiveThresholds current = balanced;

  Map<String, double> toJson() => {'explicit': explicit, 'suggestive': suggestive, 'combined': combined};
}

/// Scores from the NSFW model for one photo, or the highest scores over the
/// sampled frames of one video. A flag for human review, never proof.
class SensitiveRating {
  const SensitiveRating({required this.explicit, required this.suggestive, this.frames = 1});

  /// `porn + hentai`, 0..1.
  final double explicit;

  /// `sexy`, 0..1.
  final double suggestive;

  /// Images the scores come from: 1 for a photo, sampled frames for a video.
  final int frames;

  /// Model output order (`class_labels.txt`).
  static const labels = ['drawings', 'hentai', 'neutral', 'porn', 'sexy'];

  /// Level under [SensitiveThresholds.current].
  SensitiveLevel get level => levelWith(SensitiveThresholds.current);

  SensitiveLevel levelWith(SensitiveThresholds t) {
    if (explicit >= t.explicit) return SensitiveLevel.explicit;
    if (suggestive >= t.suggestive || explicit + suggestive >= t.combined) {
      return SensitiveLevel.suggestive;
    }
    return SensitiveLevel.safe;
  }

  bool get flagged => level != SensitiveLevel.safe;

  /// Builds a rating from one or more model outputs (one per image / frame),
  /// each in [labels] order. Each score is the maximum over the frames, so
  /// one explicit frame flags the whole video. Null when [outputs] is empty.
  static SensitiveRating? fromOutputs(List<List<double>> outputs) {
    var explicit = 0.0, suggestive = 0.0, n = 0;
    for (final o in outputs) {
      if (o.length != labels.length) continue;
      explicit = math.max(explicit, o[1] + o[3]);
      suggestive = math.max(suggestive, o[4]);
      n++;
    }
    if (n == 0) return null;
    double round(double v) => (v.clamp(0.0, 1.0) * 1000).round() / 1000;
    return SensitiveRating(explicit: round(explicit), suggestive: round(suggestive), frames: n);
  }

  Map<String, Object> toJson() => {
        'level': level.name,
        'explicit': explicit,
        'suggestive': suggestive,
        'frames': frames,
        'thresholds': SensitiveThresholds.current.toJson(),
      };

  String encode() => jsonEncode({'e': explicit, 's': suggestive, 'f': frames});

  static SensitiveRating? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      return SensitiveRating(
        explicit: (m['e'] as num).toDouble(),
        suggestive: (m['s'] as num).toDouble(),
        frames: (m['f'] as num?)?.toInt() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SensitiveRating &&
      other.explicit == explicit &&
      other.suggestive == suggestive &&
      other.frames == frames;

  @override
  int get hashCode => Object.hash(explicit, suggestive, frames);
}
