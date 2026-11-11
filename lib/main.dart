import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme/theme.dart';

import 'core/permissions/permission_handler.dart';
import 'ui/home_shell.dart';
import 'ui/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _migrateThemeMode();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: RecoverXApp()));
}

/// One-time: carry the old app-local `themeMode` choice (an index) over to the
/// shared appearance setting.
Future<void> _migrateThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final old = prefs.getInt('themeMode');
  if (old == null) return;
  if (await UiAppearance.load() == null) {
    await UiAppearance.save(ThemeMode.values[old.clamp(0, 2)]);
  }
  await prefs.remove('themeMode');
}

class RecoverXApp extends ConsumerWidget {
  const RecoverXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(appAccentProvider);

    return UiApp(
      title: 'RecoverX',
      accent: accent,
      home: const PermissionGate(child: HomeShell()),
    );
  }
}