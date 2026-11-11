import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import '../scan/scan_view_model.dart';
import '../sensitive/sensitive_controller.dart';
import '../share/browse_controller.dart';
import '../theme/theme_controller.dart';
import 'settings_controller.dart';

/// "Settings" tab: appearance, scan, content check, computer access, data.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    void set(AppSettings next) => notifier.update(next);
    final themeMode = ref.watch(themeModeProvider);
    final scan = ref.watch(scanControllerProvider);
    final checking = ref.watch(sensitiveCheckProvider.select((c) => c.running));
    final serverRunning = ref.watch(browseServerProvider.select((b) => b.running));
    final checkedCount = scan.items.where((i) => i.sensitive != null).length;

    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: UiSpace.lg),
        children: [
          UiListGroup(
            header: 'Appearance',
            children: [
              UiListTile(
                'Theme',
                icon: Icons.palette_rounded,
                trailing: UiSegmentedControl<ThemeMode>(
                  const [
                    UiSegment(ThemeMode.system, icon: Icons.brightness_auto_rounded, tooltip: 'System'),
                    UiSegment(ThemeMode.light, icon: Icons.light_mode_rounded, tooltip: 'Light'),
                    UiSegment(ThemeMode.dark, icon: Icons.dark_mode_rounded, tooltip: 'Dark'),
                  ],
                  value: themeMode,
                  size: UiSize.sm,
                  onChanged: ref.read(themeModeProvider.notifier).set,
                ),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Scan',
            footer: 'Deep scan also carves files out of unknown blobs, app databases and data '
                'hidden after images. Slower.',
            children: [
              UiListTile(
                'Deep scan by default',
                icon: Icons.manage_search_rounded,
                trailing: UiSwitch(s.deepScan, onChanged: (v) => set(s.copyWith(deepScan: v))),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Content check',
            footer: 'Sensitivity sets how high a score must be to flag an item. Changing it '
                're-labels checked items at once; the model does not run again.',
            children: [
              UiListTile(
                'Blur flagged items',
                subtitle: 'In the app and in the computer view',
                icon: Icons.blur_on_rounded,
                trailing: UiSwitch(s.blurSensitive, onChanged: (v) => set(s.copyWith(blurSensitive: v))),
              ),
              UiListTile(
                'Sensitivity',
                icon: Icons.tune_rounded,
                trailing: UiSegmentedControl<SensitivityLevel>(
                  const [
                    UiSegment(SensitivityLevel.relaxed, label: 'Low'),
                    UiSegment(SensitivityLevel.balanced, label: 'Mid'),
                    UiSegment(SensitivityLevel.strict, label: 'High'),
                  ],
                  value: s.sensitivity,
                  size: UiSize.sm,
                  onChanged: (v) => set(s.copyWith(sensitivity: v)),
                ),
              ),
              UiListTile(
                'Frames per video',
                subtitle: 'More frames catch more, but take longer',
                icon: Icons.movie_filter_rounded,
                trailing: UiSegmentedControl<int>(
                  [for (final n in AppSettings.videoFrameChoices) UiSegment(n, label: '$n')],
                  value: s.videoFrames,
                  size: UiSize.sm,
                  onChanged: checking ? null : (v) => set(s.copyWith(videoFrames: v)),
                ),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Browse on a computer',
            footer: serverRunning ? 'Port changes apply the next time the server starts.' : null,
            children: [
              UiListTile(
                'Preferred port',
                subtitle: 'Another free port is used if it is busy',
                icon: Icons.lan_rounded,
                trailing: UiSegmentedControl<int>(
                  [for (final p in AppSettings.portChoices) UiSegment(p, label: '$p')],
                  value: s.browsePort,
                  size: UiSize.sm,
                  onChanged: (v) => set(s.copyWith(browsePort: v)),
                ),
              ),
              UiListTile(
                'Stop when RecoverX is closed',
                subtitle: 'Stops the server when you leave the app',
                icon: Icons.lock_clock_rounded,
                trailing:
                    UiSwitch(s.stopServerInBackground, onChanged: (v) => set(s.copyWith(stopServerInBackground: v))),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'Data',
            footer: 'These only clear RecoverX\'s own list. Files on the phone are never touched.',
            children: [
              UiListTile(
                'Clear content-check results',
                subtitle: '${UiFormat.compact(checkedCount)} items checked',
                icon: Icons.shield_outlined,
                enabled: checkedCount > 0 && !checking,
                onTap: () async {
                  final ok = await UiDialog.confirm(context,
                      title: 'Clear content-check results?',
                      message: 'Scores are removed; run the check again to get them back.',
                      confirmLabel: 'Clear',
                      destructive: true);
                  if (ok) ref.read(scanControllerProvider.notifier).clearSensitive();
                },
              ),
              UiListTile(
                'Clear scan results',
                subtitle: '${UiFormat.compact(scan.items.length)} items',
                icon: Icons.delete_sweep_rounded,
                destructive: true,
                enabled: scan.items.isNotEmpty && !scan.isScanning,
                onTap: () async {
                  final ok = await UiDialog.confirm(context,
                      title: 'Clear results?',
                      message: 'Removes the scan list from RecoverX. Files on the phone are not touched.',
                      confirmLabel: 'Clear',
                      destructive: true);
                  if (ok) ref.read(scanControllerProvider.notifier).clearResults();
                },
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          UiListGroup(
            header: 'About',
            children: [
              const UiListTile(
                'Content-check model',
                subtitle: 'MobileNetV2 NSFW classifier (GantMan/nsfw_model, MIT). Runs on this phone.',
                icon: Icons.memory_rounded,
              ),
              UiListTile(
                'Open-source licences',
                icon: Icons.description_rounded,
                chevron: true,
                onTap: () => showLicensePage(context: context, applicationName: 'RecoverX'),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          const UiUpdateSection(storeId: 'recoverx'),
          const UiGap(UiSpace.lg),
          const UiDeveloperSection(),
        ],
      ),
    );
  }
}
