import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recoverx/data/scan_database.dart';
import 'package:recoverx/domain/sensitive_rating.dart';
import 'package:recoverx/ui/home_shell.dart';
import 'package:recoverx/ui/scan/scan_view_model.dart';
import 'package:recoverx/ui/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SensitiveThresholds.current = SensitiveThresholds.balanced);

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      scanDatabaseProvider.overrideWith((ref) {
        final db = ScanDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: UiTheme.light(), home: const HomeShell()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  testWidgets('bottom navigation opens each tab', (tester) async {
    await pumpShell(tester);
    expect(find.text('Find lost files'), findsOneWidget);

    await tester.tap(find.text('Check'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No results to check'), findsOneWidget);

    await tester.tap(find.text('Computer'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open your results on a laptop'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Deep scan by default'), findsOneWidget);
    expect(find.text('Sensitivity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings are saved and sensitivity re-labels ratings', (tester) async {
    final container = await pumpShell(tester);
    final rating = SensitiveRating.fromOutputs([
      [0.0, 0.0, 0.5, 0.5, 0.0],
    ])!;
    expect(rating.level, SensitiveLevel.safe);

    final settings = container.read(settingsProvider.notifier);
    await settings.update(settings.state.copyWith(sensitivity: SensitivityLevel.strict, deepScan: true));
    expect(rating.level, SensitiveLevel.explicit);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.sensitivity'), 'strict');
    expect(prefs.getBool('settings.deepScan'), isTrue);
  });

  test('sensitivity levels move the flag limits', () {
    const r = SensitiveRating(explicit: 0.7, suggestive: 0.1);
    expect(r.levelWith(SensitivityLevel.relaxed.thresholds), SensitiveLevel.safe);
    expect(r.levelWith(SensitivityLevel.balanced.thresholds), SensitiveLevel.explicit);
    const s = SensitiveRating(explicit: 0.3, suggestive: 0.3);
    expect(s.levelWith(SensitivityLevel.balanced.thresholds), SensitiveLevel.safe);
    expect(s.levelWith(SensitivityLevel.strict.thresholds), SensitiveLevel.suggestive);
  });
}
