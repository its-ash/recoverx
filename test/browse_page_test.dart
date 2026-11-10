import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recoverx/core/share/browse_page.dart';

/// The browse page's JavaScript lives in a Dart string, so syntax errors
/// would only show up in the browser. Parse it with Node when available.
void main() {
  final node = Process.runSync('which', ['node']).exitCode == 0;

  test('browse page script parses', () async {
    final match = RegExp(r'<script>([\s\S]*?)</script>').firstMatch(browsePageHtml);
    expect(match, isNotNull);
    final dir = await Directory.systemTemp.createTemp('browse_page');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/page.js')..writeAsStringSync(match!.group(1)!);
    final r = await Process.run('node', ['--check', file.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }, skip: node ? false : 'node not installed');

  test('video cards get browser-made thumbnails', () {
    expect(browsePageHtml, contains('thumbObserver.observe(t)'));
    expect(browsePageHtml, contains('toDataURL("image/jpeg"'));
  });
}
