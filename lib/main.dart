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
    final colorScheme = ref.watch(appColorSchemeProvider);

    return MaterialApp(
      title: 'RecoverX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(colorScheme: colorScheme),
      darkTheme: AppTheme.darkTheme(colorScheme: colorScheme),
      themeMode: themeMode,
      home: const PermissionGate(child: ScanPage()),
    );
  }
}