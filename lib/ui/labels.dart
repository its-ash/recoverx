import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../domain/file_item.dart';
import '../domain/file_metadata.dart';
import '../domain/file_signature.dart';
import '../domain/sensitive_rating.dart';
import 'scan/scan_view_model.dart';

extension FileCategoryLabel on FileCategory {
  String get label => switch (this) {
        FileCategory.image => 'Photos',
        FileCategory.video => 'Videos',
        FileCategory.audio => 'Audio',
        FileCategory.document => 'Documents',
        FileCategory.archive => 'Archives',
        FileCategory.data => 'App data',
        FileCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        FileCategory.image => Icons.image_rounded,
        FileCategory.video => Icons.movie_rounded,
        FileCategory.audio => Icons.graphic_eq_rounded,
        FileCategory.document => Icons.description_rounded,
        FileCategory.archive => Icons.folder_zip_rounded,
        FileCategory.data => Icons.storage_rounded,
        FileCategory.other => Icons.insert_drive_file_rounded,
      };
}

extension DiscoveryReasonLabel on DiscoveryReason {
  String get label => switch (this) {
        DiscoveryReason.renamed => 'Renamed',
        DiscoveryReason.hidden => 'Hidden',
        DiscoveryReason.trashed => 'Trash',
        DiscoveryReason.cache => 'Cache',
        DiscoveryReason.carved => 'Carved',
      };

  String get explanation => switch (this) {
        DiscoveryReason.renamed => 'The name or extension does not match the real file type.',
        DiscoveryReason.hidden =>
          'Hidden from the gallery: dot-name, hidden folder, .nomedia folder, or an unfinished write.',
        DiscoveryReason.trashed => 'In a trash or recycle bin, or in LOST.DIR (orphaned file).',
        DiscoveryReason.cache => 'Kept in an app or thumbnail cache.',
        DiscoveryReason.carved => 'Not a file on its own: rebuilt from bytes found inside another file.',
      };

  UiStatus get status => switch (this) {
        DiscoveryReason.renamed => UiStatus.warning,
        DiscoveryReason.hidden => UiStatus.info,
        DiscoveryReason.trashed => UiStatus.danger,
        DiscoveryReason.cache => UiStatus.neutral,
        DiscoveryReason.carved => UiStatus.accent,
      };
}

extension ResultViewLabel on ResultView {
  String get label => switch (this) {
        ResultView.all => 'All',
        ResultView.flagged => 'Flagged',
        ResultView.trashed => 'Trash',
        ResultView.hidden => 'Hidden',
        ResultView.renamed => 'Renamed',
        ResultView.carved => 'Carved',
        ResultView.cache => 'Cache',
        ResultView.truncated => 'Damaged',
        ResultView.sensitive => 'Sensitive',
      };
}

extension SensitiveLevelLabel on SensitiveLevel {
  String get label => switch (this) {
        SensitiveLevel.safe => 'Not flagged',
        SensitiveLevel.suggestive => 'Suggestive',
        SensitiveLevel.explicit => 'Explicit',
      };

  UiStatus get status => switch (this) {
        SensitiveLevel.safe => UiStatus.neutral,
        SensitiveLevel.suggestive => UiStatus.warning,
        SensitiveLevel.explicit => UiStatus.danger,
      };
}

extension ResultSortLabel on ResultSort {
  String get label => switch (this) {
        ResultSort.newest => 'Newest first',
        ResultSort.oldest => 'Oldest first',
        ResultSort.largest => 'Largest first',
        ResultSort.smallest => 'Smallest first',
        ResultSort.name => 'Name',
        ResultSort.type => 'Type',
      };
}

extension IntegrityLabel on Integrity {
  String get label => switch (this) {
        Integrity.intact => 'Complete',
        Integrity.truncated => 'Damaged / cut short',
        Integrity.unknown => 'Not checked',
      };

  UiStatus get status => switch (this) {
        Integrity.intact => UiStatus.success,
        Integrity.truncated => UiStatus.warning,
        Integrity.unknown => UiStatus.neutral,
      };
}

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
