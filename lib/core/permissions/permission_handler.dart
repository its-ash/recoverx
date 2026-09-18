import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Current permission state for storage access.
enum StoragePermissionState {
  notDetermined,
  denied,
  partial, // SAF / MediaStore only
  full, // MANAGE_EXTERNAL_STORAGE granted (Android ≤12) or Android 13+
}

class PermissionService {
  PermissionService._();

  /// Checks the current storage permission state.
  static Future<StoragePermissionState> check() async {
    if (!Platform.isAndroid) return StoragePermissionState.full;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt;

    // Android 13+ uses granular media permissions.
    if (sdk >= 33) {
      final images = await Permission.photos.isGranted;
      final videos = await Permission.videos.isGranted;
      final audio = await Permission.audio.isGranted;
      final allGranted = images && videos && audio;
      final anyGranted = images || videos || audio;
      return allGranted
          ? StoragePermissionState.full
          : anyGranted
              ? StoragePermissionState.partial
              : StoragePermissionState.denied;
    }

    // Android ≤12: request MANAGE_EXTERNAL_STORAGE for full access.
    if (sdk <= 29) {
      final storage = await Permission.storage.isGranted;
      return storage
          ? StoragePermissionState.full
          : StoragePermissionState.denied;
    }

    // Android 11–12
    final manage = await Permission.manageExternalStorage.isGranted;
    return manage
        ? StoragePermissionState.full
        : StoragePermissionState.denied;
  }

  /// Requests the appropriate storage permissions for the device's Android
  /// version. Returns the resulting state.
  static Future<StoragePermissionState> request() async {
    if (!Platform.isAndroid) return StoragePermissionState.full;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt;

    if (sdk >= 33) {
      await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
    } else if (sdk <= 29) {
      await Permission.storage.request();
    } else {
      if (!await Permission.manageExternalStorage.isGranted) {
        await openAppSettings();
      }
    }

    return check();
  }

  /// Root directories available given the current permission state.
  static Future<List<Directory>> accessibleRoots() async {
    final state = await check();
    final roots = <Directory>[];

    if (state == StoragePermissionState.full ||
        state == StoragePermissionState.partial) {
      // Common media dirs available via scoped storage.
      final storage = Directory('/storage/emulated/0');
      if (storage.existsSync()) roots.add(storage);
      for (final sub in ['DCIM', 'Pictures', 'Movies', 'Music', 'Download']) {
        final d = Directory('/storage/emulated/0/$sub');
        if (d.existsSync()) roots.add(d);
      }
    }

    if (state == StoragePermissionState.full) {
      roots.add(Directory('/storage/emulated/0/Android/data'));
      roots.add(Directory('/storage/emulated/0/Android/media'));
      roots.add(Directory('/data/data'));
    }

    return roots;
  }
}

/// Riverpod provider for the current permission state.
final permissionStateProvider =
    StateNotifierProvider<PermissionNotifier, StoragePermissionState>(
        (ref) => PermissionNotifier());

class PermissionNotifier extends StateNotifier<StoragePermissionState> {
  PermissionNotifier() : super(StoragePermissionState.notDetermined) {
    _init();
  }

  Future<void> _init() async {
    try {
      state = await PermissionService.check();
    } catch (_) {
      state = StoragePermissionState.denied;
    }
  }

  Future<void> request() async {
    try {
      state = await PermissionService.request();
    } catch (_) {
      state = StoragePermissionState.denied;
    }
  }
}

/// Wraps the app and gates the home screen behind permission state.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(permissionStateProvider);

    // While checking, show a loading indicator instead of a blank screen.
    if (state == StoragePermissionState.notDetermined) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state == StoragePermissionState.full ||
        state == StoragePermissionState.partial) {
      return child;
    }

    return _PermissionRequestScreen(state: state);
  }
}

class _PermissionRequestScreen extends ConsumerWidget {
  const _PermissionRequestScreen({required this.state});

  final StoragePermissionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_shared_rounded,
                size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('RecoverX needs storage access',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'RecoverX scans your device to find hidden, renamed, and '
              'deleted photos, videos, and documents using file signatures. '
              'Granting All Files Access lets it perform deep scans; on Android '
              '13+, individual media permissions are requested instead.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: ref.read(permissionStateProvider.notifier).request,
              icon: const Icon(Icons.security_rounded),
              label: const Text('Grant access'),
            ),
          ],
        ),
      ),
    );
  }
}