import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';

import 'home_tab.dart';
import 'scan/scan_view_model.dart';
import 'scan_page.dart';
import 'sensitive/content_check_page.dart';
import 'sensitive/sensitive_controller.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_page.dart';
import 'share/browse_controller.dart';
import 'share/computer_page.dart';

/// App shell: Home, Content check, Computer and Settings. Bottom navigation
/// on phones, a rail on tablets (`UiShell`). Tab pages keep their state.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHide);
  }

  /// Leaving the app: stop the browse server if Settings says so.
  void _onHide() {
    if (!ref.read(settingsProvider).stopServerInBackground) return;
    if (ref.read(browseServerProvider).running) ref.read(browseServerProvider.notifier).stop();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    // Loads saved settings at start-up (and applies the sensitivity limits).
    ref.watch(settingsProvider.select((s) => s.sensitivity));
    final checking = ref.watch(sensitiveCheckProvider.select((s) => s.running));
    final serverOn = ref.watch(browseServerProvider.select((s) => s.running));
    final flagged = ref.watch(resultCountsProvider.select((c) => c.byView[ResultView.sensitive] ?? 0));

    return UiShell(
      index: tab.index,
      onChanged: (i) => ref.read(homeTabProvider.notifier).state = HomeTab.values[i],
      items: [
        const UiNavItem(Icons.radar_outlined, 'Home', selectedIcon: Icons.radar_rounded),
        UiNavItem(Icons.shield_moon_outlined, 'Check',
            selectedIcon: Icons.shield_moon_rounded, badge: checking ? null : flagged, dot: checking),
        UiNavItem(Icons.laptop_outlined, 'Computer', selectedIcon: Icons.laptop_rounded, dot: serverOn),
        const UiNavItem(Icons.settings_outlined, 'Settings', selectedIcon: Icons.settings_rounded),
      ],
      pages: const [ScanPage(), ContentCheckPage(), ComputerPage(), SettingsPage()],
    );
  }
}
