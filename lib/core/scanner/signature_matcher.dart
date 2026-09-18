import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';
import '../../domain/signature_database.dart';

/// Result of a single signature match attempt.
class MatchResult {
  const MatchResult({
    required this.signature,
    required this.confidence,
  });

  final FileSignature signature;
  final MatchConfidence confidence;
}

/// Pure-Dart signature matcher. No platform deps — easily unit-testable.
class SignatureMatcher {
  SignatureMatcher({List<FileSignature>? signatures})
      : _signatures = signatures ?? SignatureDatabase.all;

  final List<FileSignature> _signatures;

  /// Attempts to identify [headerBytes]. Returns the best match or `null`.
  ///
  /// [fileBytes] (optional full file or tail chunk) is used for footer
  /// verification when available.
  MatchResult? identify({
    required List<int> headerBytes,
    List<int>? fileBytes,
  }) {
    FileSignature? best;
    MatchConfidence? bestConfidence;
    var bestScore = -1;

    for (final sig in _signatures) {
      if (!sig.matchesHeader(headerBytes)) continue;

      var score = sig.pattern.where((b) => b != null).length;
      MatchConfidence confidence;
      if (sig.footer != null && fileBytes != null) {
        confidence = sig.matchesFooter(fileBytes)
            ? MatchConfidence.high
            : MatchConfidence.medium;
        score += confidence == MatchConfidence.high ? 8 : 0;
      } else if (sig.footer != null) {
        confidence = MatchConfidence.medium;
      } else {
        confidence = score >= 4 ? MatchConfidence.high : MatchConfidence.medium;
      }

      if (score > bestScore) {
        best = sig;
        bestConfidence = confidence;
        bestScore = score;
      }
    }

    if (best == null || bestConfidence == null) return null;
    return MatchResult(signature: best, confidence: bestConfidence);
  }

  /// Convenience wrapper for a typed header.
  MatchResult? identifyHeader(Uint8List header) =>
      identify(headerBytes: header.toList());
}