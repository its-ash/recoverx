import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';

/// What a file's location and name say about it.
class LocationInfo {
  const LocationInfo({
    required this.reasons,
    this.originalName,
    this.sourceApp,
    this.notes = const {},
  });

  final Set<DiscoveryReason> reasons;

  /// Name before the system renamed it (trash / pending prefixes removed).
  final String? originalName;
  final String? sourceApp;

  /// Extra facts for the metadata view (e.g. trash expiry).
  final Map<String, String> notes;
}

/// Classifies files by path and name. Pure Dart, no I/O.
class LocationClassifier {
  const LocationClassifier();

  static final _trashedName = RegExp(r'^\.trashed-(\d{9,11})-(.+)$');
  static final _pendingName = RegExp(r'^\.pending-(\d{9,11})-(.+)$');

  static const _trashDirs = {
    '.trash', '.trashes', 'trash', '.trashbin', '.recycle', '.recyclebin', //
    'recycle bin', 'recyclebin', '.globaltrash', '.localtrash', '.deleted',
    'recentlydeleted', 'recently deleted', '.recently_deleted', 'lost.dir',
    '.recentlydeleted', 'deleted', '.trashed', 'bin', '.bin',
  };

  static const _cacheDirs = {
    'cache', '.cache', 'caches', 'code_cache', '.thumbnails', 'thumbnails', //
    '.thumbs', 'thumbs', 'thumbnail', 'imagecache', 'image_cache', 'img_cache',
    'glide', 'image_manager_disk_cache', 'fresco', 'picasso-cache', 'tmp',
    'temp', '.temp', '.tmp', 'diskcache', 'http-cache', 'exo', 'exoplayer',
    'video_cache', 'videocache', '.videocache', 'mediacache', '.shared',
  };

  /// [underNoMedia]: a folder above the file has a `.nomedia` marker, which
  /// hides it from the gallery.
  LocationInfo classify({
    required String path,
    required FileType type,
    bool underNoMedia = false,
  }) {
    final slash = path.lastIndexOf('/');
    final name = path.substring(slash + 1);
    final dirs = path.substring(0, slash < 0 ? 0 : slash).split('/')
      ..removeWhere((d) => d.isEmpty);
    final lowerDirs = dirs.map((d) => d.toLowerCase()).toList();

    final reasons = <DiscoveryReason>{};
    final notes = <String, String>{};
    String? originalName;

    // ── Trash ──
    final t = _trashedName.firstMatch(name);
    if (t != null) {
      reasons.add(DiscoveryReason.trashed);
      originalName = t[2];
      final expiry = int.tryParse(t[1]!);
      if (expiry != null) {
        final when = DateTime.fromMillisecondsSinceEpoch(expiry * 1000);
        notes['Trash expires'] = _fmtDate(when);
      }
    }
    final p = _pendingName.firstMatch(name);
    if (p != null) {
      // MediaStore "pending" files: a capture / download / save that never
      // finished. Often the only copy of something deleted mid-write.
      reasons.add(DiscoveryReason.hidden);
      originalName = p[2];
      notes['Pending'] = 'Interrupted write (never published)';
    }
    if (lowerDirs.any(_isTrashDir)) reasons.add(DiscoveryReason.trashed);
    if (lowerDirs.contains('lost.dir')) {
      notes['LOST.DIR'] = 'Orphaned file recovered by a filesystem check';
    }

    // ── Cache ──
    final lowerName = name.toLowerCase();
    final isCache = lowerDirs.any(_cacheDirs.contains) ||
        lowerName.startsWith('.thumbdata') ||
        lowerName.startsWith('thumbdata') ||
        lowerName.startsWith('imgcache');
    if (isCache) reasons.add(DiscoveryReason.cache);

    // ── Hidden ──
    final hiddenDir = dirs.any((d) => d.startsWith('.'));
    if (underNoMedia || hiddenDir || (name.startsWith('.') && t == null && p == null)) {
      reasons.add(DiscoveryReason.hidden);
    }

    // ── Renamed / disguised ──
    final effective = originalName ?? name;
    final dot = effective.lastIndexOf('.');
    final ext = dot > 0 ? effective.substring(dot + 1) : '';
    final appData = type.category == FileCategory.data;
    if (ext.isEmpty) {
      // App databases and cache blobs are routinely extension-less.
      if (!appData && !isCache) reasons.add(DiscoveryReason.renamed);
    } else if (!type.acceptsExtension(ext)) {
      if (!isCache || _looksLikeMediaExt(ext)) {
        reasons.add(DiscoveryReason.renamed);
      }
    }

    return LocationInfo(
      reasons: reasons,
      originalName: originalName,
      sourceApp: sourceAppFor(lowerDirs, lowerName),
      notes: notes,
    );
  }

  static bool _isTrashDir(String d) =>
      _trashDirs.contains(d) || d.contains('trash') || d.contains('recycle');

  static const _mediaExts = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'mp4', 'mov', '3gp', 'mkv', //
    'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'amr', 'pdf', 'doc', 'docx',
    'xls', 'xlsx', 'ppt', 'pptx', 'zip', 'apk', 'txt',
  };

  /// A cache file named like a *different* known type is still suspicious.
  static bool _looksLikeMediaExt(String ext) =>
      _mediaExts.contains(ext.toLowerCase());

  /// Best-effort app / folder label for a path.
  static String? sourceAppFor(List<String> lowerDirs, String lowerName) {
    final joined = '/${lowerDirs.join('/')}/';
    bool has(String s) => joined.contains(s);

    if (has('/.statuses/')) return 'WhatsApp Status';
    if (has('com.whatsapp.w4b') || has('whatsapp business')) {
      return 'WhatsApp Business';
    }
    if (has('whatsapp')) return 'WhatsApp';
    if (has('telegram')) return 'Telegram';
    if (has('org.thoughtcrime.securesms') || has('/signal')) return 'Signal';
    if (has('instagram')) return 'Instagram';
    if (has('com.facebook.orca') || has('/messenger')) return 'Messenger';
    if (has('com.facebook') || has('/facebook')) return 'Facebook';
    if (has('snapchat')) return 'Snapchat';
    if (has('viber')) return 'Viber';
    if (has('tencent/micromsg') || has('wechat')) return 'WeChat';
    if (has('jp.naver.line') || has('/line/')) return 'LINE';
    if (has('com.google.android.apps.photos')) return 'Google Photos';
    if (has('gallery3d') || has('com.sec.android.gallery')) return 'Gallery';
    if (has('miui/gallery')) return 'MIUI Gallery';
    if (has('lost.dir')) return 'LOST.DIR';
    if (has('screenshots')) return 'Screenshots';
    if (has('screenrecord') || has('screen recordings')) {
      return 'Screen recordings';
    }
    if (has('call') && (has('record') || has('recordings'))) {
      return 'Call recordings';
    }
    if (has('/recordings/') || has('voice recorder') || has('/sounds/')) {
      return 'Voice recordings';
    }
    if (has('/dcim/camera/') || has('/dcim/100andro/') || has('/camera/')) {
      return 'Camera';
    }
    if (has('/bluetooth/')) return 'Bluetooth';
    if (has('/download/') || has('/downloads/')) return 'Downloads';
    if (has('/dcim/')) return 'DCIM';
    if (has('/pictures/')) return 'Pictures';
    if (has('/movies/')) return 'Movies';
    if (has('/music/')) return 'Music';
    if (has('/documents/')) return 'Documents';
    if (has('/android/data/') || has('/android/media/')) {
      final i = lowerDirs.indexWhere((d) => d == 'data' || d == 'media');
      if (i >= 0 && i + 1 < lowerDirs.length) return lowerDirs[i + 1];
    }
    if (lowerName.startsWith('.thumbdata')) return 'Gallery thumbnails';
    return null;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
