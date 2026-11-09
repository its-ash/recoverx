import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theme/theme.dart';

import 'core/permissions/permission_handler.dart';
import 'ui/scan_page.dart';
import 'ui/theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: RecoverXApp()));
}

class RecoverXApp extends ConsumerWidget {
  const RecoverXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(appAccentProvider);

    return MaterialApp(
      title: 'RecoverX',
      debugShowCheckedModeBanner: false,
      theme: UiTheme.light(accent: accent),
      darkTheme: UiTheme.dark(accent: accent),
      themeMode: themeMode,
      home: const PermissionGate(child: ScanPage()),
    );
  }
}