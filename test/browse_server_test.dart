import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recoverx/core/share/browse_server.dart';
import 'package:recoverx/domain/file_item.dart';
import 'package:recoverx/domain/sensitive_rating.dart';
import 'package:recoverx/domain/signature_database.dart';

void main() {
  late Directory dir;
  late File whole;
  late File container;
  late File secret;
  late List<FileItem> items;
  late BrowseServer server;
  late HttpClient client;
  late int port;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('browse_test');
    whole = File('${dir.path}/clip.mp4')..writeAsBytesSync(List.generate(1000, (i) => i % 256));
    container = File('${dir.path}/cache.db')..writeAsBytesSync(List.generate(500, (i) => i % 256));
    secret = File('${dir.path}/secret.txt')..writeAsStringSync('not in results');
    items = [
      FileItem(path: whole.path, size: 1000, type: FileTypes.mp4, matchConfidence: MatchConfidence.high),
      FileItem(
          path: container.path,
          size: 100,
          sourceOffset: 200,
          type: FileTypes.jpeg,
          matchConfidence: MatchConfidence.high,
          reasons: const {DiscoveryReason.carved}),
    ];
    server = BrowseServer(items: () => items, pin: '123456');
    port = await server.start(port: 0, bind: InternetAddress.loopbackIPv4);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await dir.delete(recursive: true);
  });

  Uri url(String path, [Map<String, String>? q]) =>
      Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path, queryParameters: q);

  Future<HttpClientResponse> get(String path, {Map<String, String>? q, Cookie? cookie, String? range}) async {
    final req = await client.getUrl(url(path, q));
    req.followRedirects = false;
    if (cookie != null) req.cookies.add(cookie);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    return req.close();
  }

  Future<HttpClientResponse> login(String pin) async {
    final req = await client.postUrl(url('/login'));
    req.followRedirects = false;
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write('pin=$pin');
    return req.close();
  }

  Future<Cookie> session() async {
    final res = await login('123456');
    await res.drain<void>();
    return res.cookies.singleWhere((c) => c.name == 'rx_session');
  }

  Future<List<int>> body(HttpClientResponse r) async => [for (final c in await r.toList()) ...c];

  test('needs a PIN: login page, 401 for data', () async {
    final page = await get('/');
    expect(page.statusCode, 200);
    expect(utf8.decode(await body(page)), contains('Enter the PIN'));
    final api = await get('/api/items');
    expect(api.statusCode, 401);
    await api.drain<void>();
    final file = await get('/file', q: {'id': whole.path});
    expect(file.statusCode, 401);
    await file.drain<void>();
  });

  test('wrong PIN is rejected without a session', () async {
    final res = await login('000000');
    await res.drain<void>();
    expect(res.statusCode, HttpStatus.seeOther);
    expect(res.headers.value(HttpHeaders.locationHeader), '/?e=1');
    expect(res.cookies.where((c) => c.name == 'rx_session'), isEmpty);
  });

  test('locks after too many wrong PINs', () async {
    for (var i = 0; i < BrowseServer.maxPinAttempts; i++) {
      await (await login('000000')).drain<void>();
    }
    final res = await login('123456');
    await res.drain<void>();
    expect(res.cookies.where((c) => c.name == 'rx_session'), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lists scan results', () async {
    final c = await session();
    final res = await get('/api/items', cookie: c);
    expect(res.statusCode, 200);
    final list = jsonDecode(utf8.decode(await body(res))) as List;
    expect(list, hasLength(2));
    expect(list[1]['offset'], 200);
    expect(list[1]['reasons'], ['carved']);
  });

  test('streams whole files and byte ranges', () async {
    final c = await session();
    final full = await get('/file', q: {'id': whole.path}, cookie: c);
    expect(full.statusCode, 200);
    expect(full.headers.contentType?.mimeType, 'video/mp4');
    expect(await body(full), whole.readAsBytesSync());

    final part = await get('/file', q: {'id': whole.path}, cookie: c, range: 'bytes=10-19');
    expect(part.statusCode, HttpStatus.partialContent);
    expect(part.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-19/1000');
    expect(await body(part), List.generate(10, (i) => 10 + i));

    final tail = await get('/file', q: {'id': whole.path}, cookie: c, range: 'bytes=-5');
    expect(await body(tail), List.generate(5, (i) => (995 + i) % 256));

    final bad = await get('/file', q: {'id': whole.path}, cookie: c, range: 'bytes=5000-');
    expect(bad.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    await bad.drain<void>();
  });

  test('serves carved items from their offset', () async {
    final c = await session();
    final res = await get('/file', q: {'id': '${container.path}#200'}, cookie: c);
    expect(res.statusCode, 200);
    expect(await body(res), List.generate(100, (i) => (200 + i) % 256));
  });

  test('never serves paths outside the results', () async {
    final c = await session();
    final res = await get('/file', q: {'id': secret.path}, cookie: c);
    expect(res.statusCode, 404);
    await res.drain<void>();
  });

  test('downloads are hashed and listed in the download log', () async {
    final c = await session();
    final res = await get('/file', q: {'id': '${container.path}#200', 'download': '1'}, cookie: c);
    expect(res.statusCode, 200);
    expect(res.headers.value('content-disposition'), startsWith('attachment'));
    final bytes = await body(res);
    final expected = sha256.convert(bytes).toString();
    // The log entry is added after the response closes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.downloads.single.sha256, expected);
    expect(server.downloads.single.client, '127.0.0.1');

    final report = await get('/downloads/report.json', cookie: c);
    final json = jsonDecode(utf8.decode(await body(report))) as Map<String, Object?>;
    final files = json['files'] as List;
    expect(files.single['sha256'], expected);
    expect(files.single['carvedOffset'], 200);

    final csv = await get('/downloads/manifest.csv', cookie: c);
    expect(utf8.decode(await body(csv)), contains(expected));

    // Viewing (no download flag) and ranged reads are not logged.
    await (await get('/file', q: {'id': whole.path}, cookie: c)).drain<void>();
    await (await get('/file', q: {'id': whole.path, 'download': '1'}, cookie: c, range: 'bytes=0-9')).drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.downloads, hasLength(1));
  });

  test('hash endpoint matches the served bytes', () async {
    final c = await session();
    final res = await get('/api/hash', q: {'id': '${container.path}#200'}, cookie: c);
    final json = jsonDecode(utf8.decode(await body(res))) as Map<String, Object?>;
    expect(json['sha256'], sha256.convert(List.generate(100, (i) => (200 + i) % 256)).toString());
  });

  test('download log needs a session', () async {
    final res = await get('/downloads/report.json');
    expect(res.statusCode, 401);
    await res.drain<void>();
  });

  test('item list shows sensitive ratings applied after start', () async {
    var rev = 0;
    await server.stop();
    server = BrowseServer(items: () => items, revision: () => rev, pin: '123456');
    port = await server.start(port: 0, bind: InternetAddress.loopbackIPv4);
    final c = await session();
    Future<List> list() async => jsonDecode(utf8.decode(await body(await get('/api/items', cookie: c)))) as List;
    expect((await list())[0]['sensitive'], isNull);
    items[0].sensitive = SensitiveRating.fromOutputs([
      [0.0, 0.0, 0.1, 0.9, 0.0],
    ]);
    rev++;
    final s = (await list())[0]['sensitive'] as Map;
    expect(s['level'], 'explicit');
    expect(s['explicit'], 0.9);
  });

  test('sees items added after start', () async {
    final c = await session();
    items.add(FileItem(path: secret.path, size: 14, type: FileTypes.jpeg, matchConfidence: MatchConfidence.low));
    final res = await get('/file', q: {'id': secret.path}, cookie: c);
    expect(res.statusCode, 200);
    await res.drain<void>();
  });
}
