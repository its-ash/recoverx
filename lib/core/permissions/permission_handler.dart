import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import '../storage/storage_volumes.dart';

/// Current permission state for storage access.
enum StoragePermissionState {
  notDetermined,
  denied,

  /// Only media files the system indexes (Android 13+ media permissions).
  /// Hidden, renamed and non-media files are out of reach.
  partial,

  /// All-files access: every file on shared storage and SD cards.
  full,
}

class PermissionService {
  PermissionService._();

  static Future<int> _sdk() async =>
      (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  static Future<StoragePermissionState> check() async {
    if (!Platform.isAndroid) return StoragePermissionState.full;
    final sdk = await _sdk();

    if (sdk >= 30) {
      if (await Permission.manageExternalStorage.isGranted) {
        return StoragePermissionState.full;
      }
      if (sdk >= 33 &&
          (await Permission.photos.isGranted ||
              await Permission.videos.isGranted ||
              await Permission.audio.isGranted)) {
        return StoragePermissionState.partial;
      }
      if (sdk < 33 && await Permission.storage.isGranted) {
        return StoragePermissionState.partial;
      }
      return StoragePermissionState.denied;
    }
    return await Permission.storage.isGranted
        ? StoragePermissionState.full
        : StoragePermissionState.denied;
  }

  /// Asks for all-files access (Android 11+) or storage (Android 8–10).
  static Future<StoragePermissionState> requestFull() async {
    if (!Platform.isAndroid) return StoragePermissionState.full;
    final sdk = await _sdk();
    if (sdk >= 30) {
      // Opens the system "All files access" page for this app.
      await Permission.manageExternalStorage.request();
    } else {
      await Permission.storage.request();
    }
    return check();
  }

  /// Media-only fallback for users who will not grant all-files access.
  static Future<StoragePermissionState> requestMediaOnly() async {
    if (!Platform.isAndroid) return StoragePermissionState.full;
    final sdk = await _sdk();
    if (sdk >= 33) {
      await [Permission.photos, Permission.videos, Permission.audio].request();
    } else {
      await Permission.storage.request();
    }
    return check();
  }

  /// Folders to scan: every readable storage volume.
  static List<String> scanRoots() =>
      StorageVolumes.list().map((v) => v.path).toList();
}

/// Riverpod provider for the current permission state.
final permissionStateProvider =
    StateNotifierProvider<PermissionNotifier, StoragePermissionState>(
        (ref) => PermissionNotifier());

class PermissionNotifier extends StateNotifier<StoragePermissionState> {
  PermissionNotifier() : super(StoragePermissionState.notDetermined) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      state = await PermissionService.check();
    } catch (_) {
      state = StoragePermissionState.denied;
    }
  }

  Future<void> requestFull() async {
    try {
      state = await PermissionService.requestFull();
    } catch (_) {
      await refresh();
    }
  }

  Future<void> requestMediaOnly() async {
    try {
      state = await PermissionService.requestMediaOnly();
    } catch (_) {
      await refresh();
    }
  }
}

/// Gates [child] behind storage permission. Re-checks when the user comes
/// back from the system settings page.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(permissionStateProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(permissionStateProvider);
    return switch (state) {
      StoragePermissionState.notDetermined =>
        const Scaffold(body: Center(child: UiSpinner(size: 28))),
      StoragePermissionState.full ||
      StoragePermissionState.partial =>
        widget.child,
      StoragePermissionState.denied => const _PermissionRequestScreen(),
    };
  }
}

class _PermissionRequestScreen extends ConsumerWidget {
  const _PermissionRequestScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(permissionStateProvider.notifier);
    return UiScaffold(
      maxWidth: 560,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const UiEmptyState(
                icon: Icons.folder_shared_rounded,
                title: 'RecoverX needs All files access',
                message:
                    'To find hidden, renamed, trashed and orphaned files, '
                    'RecoverX must read every file on the phone and SD card. '
                    'It only reads during a scan; nothing is changed or uploaded.',
              ),
              const UiGap(UiSpace.lg),
              UiButton(
                'Allow all files access',
                icon: Icons.security_rounded,
                expand: true,
                onPressed: notifier.requestFull,
              ),
              const UiGap(UiSpace.sm),
              UiButton(
                'Media only (limited scan)',
                variant: UiButtonVariant.ghost,
                expand: true,
                onPressed: notifier.requestMediaOnly,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
