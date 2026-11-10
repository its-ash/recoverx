import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme/theme.dart';

/// The scan card swaps a pulsing pill for a "Paused" pill and back. Without
/// distinct keys UiStatusPill reuses its State and creates a second ticker,
/// which crashes on resume.
void main() {
  Widget pill(bool paused) => MaterialApp(
        theme: UiTheme.light(),
        home: Scaffold(
          body: Row(children: [
            if (paused)
              const UiStatusPill('Paused', key: ValueKey('pill-paused'), status: UiStatus.warning)
            else
              const UiStatusPill('Deep', key: ValueKey('pill-running'), status: UiStatus.accent, pulse: true),
          ]),
        ),
      );

  testWidgets('pause and resume the scan pill repeatedly', (tester) async {
    for (final paused in [false, true, false, true, false]) {
      await tester.pumpWidget(pill(paused));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Deep'), findsOneWidget);
  });
}
