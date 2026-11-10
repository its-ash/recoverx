import 'dart:io';

/// A mounted storage volume (internal shared storage, SD card, USB-OTG).
class StorageVolume {
  const StorageVolume({required this.path, required this.label, required this.removable});

  final String path;
  final String label;
  final bool removable;
}

class StorageVolumes {
  StorageVolumes._();

  static const internalPath = '/storage/emulated/0';

  /// Lists readable volumes. Internal storage first.
  static List<StorageVolume> list() {
    final out = <StorageVolume>[];
    if (Directory(internalPath).existsSync()) {
      out.add(const StorageVolume(
          path: internalPath, label: 'Internal storage', removable: false));
    }
    // Other Android users / work profile / secure folder, when readable.
    try {
      for (final e in Directory('/storage/emulated').listSync()) {
        final name = e.path.split('/').last;
        if (e is Directory && name != '0' && int.tryParse(name) != null) {
          if (_readable(e.path)) {
            out.add(StorageVolume(
                path: e.path, label: 'User $name storage', removable: false));
          }
        }
      }
    } catch (_) {}
    // Removable volumes: /storage/XXXX-XXXX (SD card, USB-OTG).
    try {
      for (final e in Directory('/storage').listSync()) {
        final name = e.path.split('/').last;
        if (e is! Directory || name == 'emulated' || name == 'self') continue;
        if (_readable(e.path)) {
          out.add(StorageVolume(
              path: e.path, label: 'Removable ($name)', removable: true));
        }
      }
    } catch (_) {}
    return out;
  }

  static bool _readable(String path) {
    try {
      Directory(path).listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The volume that contains [path], if any.
  static StorageVolume? volumeOf(String path, List<StorageVolume> volumes) {
    StorageVolume? best;
    for (final v in volumes) {
      if (path == v.path || path.startsWith('${v.path}/')) {
        if (best == null || v.path.length > best.path.length) best = v;
      }
    }
    return best;
  }
}
