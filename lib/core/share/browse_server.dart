import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../domain/file_item.dart';
import 'browse_page.dart';

/// A LAN address the server can be reached on.
typedef LanAddress = ({String interface, String address});

/// One file fully sent to a browser as a download.
class BrowseDownload {
  const BrowseDownload({required this.item, required this.sha256, required this.at, required this.client});

  final FileItem item;

  /// SHA-256 of the exact bytes read from the device and sent.
  final String sha256;
  final DateTime at;

  /// IP address of the computer that downloaded it.
  final String client;
}

/// Read-only web view of the scan results for other computers on the same
/// Wi-Fi or hotspot.
///
/// * Serves only items that are in the scan results: never arbitrary paths.
/// * Opens files read-only and streams them (HTTP Range for video seeking).
///   Carved items are served from their byte range inside the container.
/// * A 6-digit PIN, shown in the app, guards access. After
///   [maxPinAttempts] wrong PINs the login is locked until restart.
/// * Downloads are hashed (SHA-256) while they are sent and logged in a
///   download report the computer can fetch (`/downloads/report.json`,
///   `/downloads/manifest.csv`), so each copy can be verified.
/// * Nothing is written to the device.
class BrowseServer {
  BrowseServer({required this.items, this.revision, this.config, this.onDownload, String? pin, Random? random})
      : _random = random ?? Random.secure(),
        pin = pin ?? _newPin(random ?? Random.secure());

  /// Current scan results. Read on every request so the list stays live.
  final List<FileItem> Function() items;

  /// Changes whenever items change in place (e.g. sensitive-content ratings),
  /// so the cached item list is rebuilt.
  final int Function()? revision;

  /// Page options from the app's settings (e.g. `{'blur': true}`), served at
  /// `/api/config`.
  final Map<String, Object> Function()? config;

  /// Called after each completed download.
  final void Function(BrowseDownload)? onDownload;

  /// Completed downloads, oldest first.
  final downloads = <BrowseDownload>[];

  final String pin;
  final Random _random;

  static const maxPinAttempts = 10;
  static const _cookie = 'rx_session';
  static const _chunk = 256 * 1024;

  HttpServer? _server;
  final _sessions = <String>{};
  int _failedLogins = 0;

  List<FileItem>? _indexedList;
  int _indexedLength = -1;
  int? _indexedRevision;
  Map<String, FileItem> _index = const {};
  String? _json;
  final _hashes = <String, String>{};

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Starts listening on all IPv4 interfaces. Tries [port] first, then any
  /// free port.
  Future<int> start({int port = 8080, InternetAddress? bind}) async {
    if (_server != null) return _server!.port;
    final address = bind ?? InternetAddress.anyIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(address, port);
    } on SocketException {
      server = await HttpServer.bind(address, 0);
    }
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    server.listen((req) => _handle(req).catchError((Object _) {
          try {
            req.response.close();
          } catch (_) {}
        }));
    return server.port;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _sessions.clear();
    await s?.close(force: true);
  }

  /// Non-loopback IPv4 addresses, Wi-Fi and hotspot first.
  static Future<List<LanAddress>> lanAddresses() async {
    final out = <LanAddress>[];
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) out.add((interface: i.name, address: a.address));
      }
    }
    int rank(LanAddress a) {
      final n = a.interface.toLowerCase();
      if (n.startsWith('wlan') || n.startsWith('ap') || n.startsWith('swlan')) return 0;
      if (n.startsWith('eth') || n.startsWith('rndis') || n.startsWith('usb')) return 1;
      if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('tun')) return 3;
      return 2;
    }

    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  static String _newPin(Random r) => List.generate(6, (_) => r.nextInt(10)).join();

  String _newSession() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // ───────────────────────── Routing ─────────────────────────

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Cache-Control', 'no-store');
    final path = req.uri.path;

    if (path == '/login' && req.method == 'POST') return _login(req);
    if (req.method != 'GET' && req.method != 'HEAD') return _status(res, HttpStatus.methodNotAllowed);

    if (!_authed(req)) {
      if (path == '/') {
        final error = _failedLogins >= maxPinAttempts
            ? 'Too many wrong PINs. Restart the server in the app.'
            : req.uri.queryParameters['e'] == '1'
                ? 'Wrong PIN.'
                : null;
        return _html(res, loginPageHtml(error: error));
      }
      return _status(res, HttpStatus.unauthorized);
    }

    switch (path) {
      case '/':
        return _html(res, browsePageHtml);
      case '/api/items':
        return _items(res);
      case '/file':
        return _file(req);
      case '/api/hash':
        return _hash(req);
      case '/api/config':
        return _send(res, ContentType.json, jsonEncode(config?.call() ?? const {'blur': true}));
      case '/downloads/report.json':
        return _send(res, ContentType.json, downloadReportJson(), attachment: 'recoverx_downloads.json');
      case '/downloads/manifest.csv':
        return _send(res, ContentType('text', 'csv', charset: 'utf-8'), downloadManifestCsv(),
            attachment: 'recoverx_downloads.csv');
      case '/logout':
        _sessions.remove(_sessionOf(req));
        res.headers.set('Set-Cookie', '$_cookie=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict');
        return _redirect(res, '/');
      default:
        return _status(res, HttpStatus.notFound);
    }
  }

  String? _sessionOf(HttpRequest req) {
    for (final c in req.cookies) {
      if (c.name == _cookie) return c.value;
    }
    return null;
  }

  bool _authed(HttpRequest req) {
    final s = _sessionOf(req);
    return s != null && _sessions.contains(s);
  }

  Future<void> _login(HttpRequest req) async {
    final res = req.response;
    if (_failedLogins >= maxPinAttempts) return _redirect(res, '/');
    final bytes = <int>[];
    await for (final chunk in req.timeout(const Duration(seconds: 5))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024) return _status(res, HttpStatus.requestEntityTooLarge);
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    final given = Uri.splitQueryString(body)['pin']?.trim() ?? '';
    if (!_constantTimeEquals(given, pin)) {
      _failedLogins++;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return _redirect(res, '/?e=1');
    }
    final session = _newSession();
    _sessions.add(session);
    res.headers.set('Set-Cookie', '$_cookie=$session; Path=/; HttpOnly; SameSite=Strict');
    return _redirect(res, '/');
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ───────────────────────── Items ─────────────────────────

  /// Rebuilds the id index when the result list changes (new scan, or more
  /// items appended during a scan).
  void _refreshIndex() {
    final list = items();
    final rev = revision?.call();
    if (identical(list, _indexedList) && list.length == _indexedLength && rev == _indexedRevision) return;
    _indexedList = list;
    _indexedLength = list.length;
    _indexedRevision = rev;
    _index = {for (final i in list) i.id: i};
    _json = null;
  }

  Future<void> _items(HttpResponse res) async {
    _refreshIndex();
    final json = _json ??= jsonEncode([for (final i in _indexedList!) itemJson(i)]);
    res.headers.contentType = ContentType.json;
    res.write(json);
    await res.close();
  }

  /// Fields the web page shows. Public for tests.
  static Map<String, Object?> itemJson(FileItem i) {
    final m = i.metadata;
    return {
      'id': i.id,
      'name': i.suggestedName,
      'diskName': i.fileName,
      'path': i.path,
      'type': i.displayName,
      'ext': i.detectedExtension,
      'mime': i.detectedMimeType,
      'category': i.category.name,
      'size': i.size,
      'offset': i.sourceOffset,
      'reasons': [for (final r in i.reasons) r.name],
      'modified': i.lastModified?.toIso8601String(),
      'taken': m?.takenAt?.toIso8601String(),
      'app': i.sourceApp,
      'integrity': i.integrity.name,
      'confidence': i.matchConfidence.name,
      'recovered': i.isRecovered,
      'meta': m?.toDisplayMap() ?? const <String, String>{},
      'sensitive': i.sensitive?.toJson(),
    };
  }

  // ───────────────────────── Files ─────────────────────────

  /// Types a browser may render inline. Anything else (HTML, SVG, scripts,
  /// unknown) is sent as a download so it cannot run in this origin.
  static bool _inlineSafe(String mime) {
    if (mime == 'image/svg+xml') return false;
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        mime.startsWith('audio/') ||
        mime == 'application/pdf' ||
        mime == 'text/plain';
  }

  Future<void> _file(HttpRequest req) async {
    final res = req.response;
    final id = req.uri.queryParameters['id'];
    _refreshIndex();
    final item = id == null ? null : _index[id];
    if (item == null) return _status(res, HttpStatus.notFound);

    final RandomAccessFile raf;
    try {
      raf = await File(item.path).open();
    } on FileSystemException {
      return _status(res, HttpStatus.gone);
    }
    try {
      final base = item.sourceOffset ?? 0;
      final available = max(0, min(item.size, await raf.length() - base));
      final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader), available);
      if (range == _badRange) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$available');
        await res.close();
        return;
      }

      final download = req.uri.queryParameters['download'] != null;
      final inline = _inlineSafe(item.detectedMimeType) && !download;
      final name = item.suggestedName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      res.headers
        ..contentType = inline ? ContentType.parse(item.detectedMimeType) : ContentType.binary
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set('Content-Disposition', '${inline ? 'inline' : 'attachment'}; filename="$name"');
      final known = _hashes[item.id];
      if (known != null && range == null) res.headers.set('X-Content-SHA256', known);

      final (start, end) = range ?? (0, available - 1);
      final length = available == 0 ? 0 : end - start + 1;
      if (range != null) {
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$available');
      }
      res.contentLength = length;
      if (req.method == 'HEAD' || length == 0) {
        await res.close();
        return;
      }
      // Whole-file downloads are hashed on the way out and logged, so the
      // copy on the computer can be checked against the report.
      final logIt = download && range == null;
      final digest = _DigestSink();
      final hasher = logIt ? sha256.startChunkedConversion(digest) : null;
      var sent = 0;
      await res.addStream(_read(raf, base + start, length).map((chunk) {
        hasher?.add(chunk);
        sent += chunk.length;
        return chunk;
      }));
      await res.close();
      if (hasher != null && sent == length) {
        hasher.close();
        final hex = digest.value.toString();
        _hashes[item.id] = hex;
        final record = BrowseDownload(
          item: item,
          sha256: hex,
          at: DateTime.now(),
          client: req.connectionInfo?.remoteAddress.address ?? '?',
        );
        downloads.add(record);
        onDownload?.call(record);
      }
    } finally {
      await raf.close();
    }
  }

  /// `{"sha256": "..."}` of an item's bytes (the carved range for carved
  /// items). Cached per item.
  Future<void> _hash(HttpRequest req) async {
    final res = req.response;
    final id = req.uri.queryParameters['id'];
    _refreshIndex();
    final item = id == null ? null : _index[id];
    if (item == null) return _status(res, HttpStatus.notFound);
    var hex = _hashes[item.id];
    if (hex == null) {
      final RandomAccessFile raf;
      try {
        raf = await File(item.path).open();
      } on FileSystemException {
        return _status(res, HttpStatus.gone);
      }
      try {
        final base = item.sourceOffset ?? 0;
        final length = max(0, min(item.size, await raf.length() - base));
        final digest = _DigestSink();
        final hasher = sha256.startChunkedConversion(digest);
        await _read(raf, base, length).forEach(hasher.add);
        hasher.close();
        hex = _hashes[item.id] = digest.value.toString();
      } finally {
        await raf.close();
      }
    }
    return _send(res, ContentType.json, jsonEncode({'id': item.id, 'sha256': hex}));
  }

  // ───────────────────────── Download report ─────────────────────────

  /// Download log in the same shape as the export `report.json`.
  String downloadReportJson() => const JsonEncoder.withIndent('  ').convert({
        'tool': 'RecoverX',
        'kind': 'browser downloads',
        'generatedAt': DateTime.now().toIso8601String(),
        'hashAlgorithm': 'SHA-256',
        'note': 'Each sha256 is computed from the bytes read on the phone while they were sent. '
            'Hash the downloaded file on this computer and compare. sensitiveCheck is an '
            'automatic on-device model score for review, not a finding.',
        'files': [
          for (final d in downloads)
            {
              'downloadedFile': d.item.suggestedName,
              'sha256': d.sha256,
              'downloadedAt': d.at.toIso8601String(),
              'client': d.client,
              'type': d.item.type.id,
              'mime': d.item.detectedMimeType,
              'sizeBytes': d.item.size,
              'originalPath': d.item.path,
              'carvedOffset': d.item.sourceOffset,
              'originalName': d.item.originalName,
              'reasons': [for (final r in d.item.reasons) r.name],
              'sourceApp': d.item.sourceApp,
              'integrity': d.item.integrity.name,
              'confidence': d.item.matchConfidence.name,
              'fsModified': d.item.lastModified?.toIso8601String(),
              'metadata': d.item.metadata?.toJson(),
              'sensitiveCheck': d.item.sensitive?.toJson(),
            },
        ],
      });

  String downloadManifestCsv() {
    String csv(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final out = StringBuffer()
      ..writeln('downloaded_file,sha256,downloaded_at,client,type,mime,size_bytes,'
          'original_path,carved_offset,original_name,reasons,source_app,integrity,fs_modified,'
          'sensitive_level,sensitive_explicit,sensitive_suggestive');
    for (final d in downloads) {
      final i = d.item;
      out.writeln([
        i.suggestedName,
        d.sha256,
        d.at.toIso8601String(),
        d.client,
        i.type.id,
        i.detectedMimeType,
        i.size,
        i.path,
        i.sourceOffset,
        i.originalName,
        i.reasons.map((r) => r.name).join(' '),
        i.sourceApp,
        i.integrity.name,
        i.lastModified?.toIso8601String(),
        i.sensitive?.level.name,
        i.sensitive?.explicit,
        i.sensitive?.suggestive,
      ].map(csv).join(','));
    }
    return out.toString();
  }

  static const _badRange = (-1, -1);

  /// Parses a single `bytes=` range. Null means the whole file.
  static (int, int)? _parseRange(String? header, int size) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring(6).split(',').first.trim();
    final dash = spec.indexOf('-');
    if (dash < 0 || size == 0) return _badRange;
    final a = spec.substring(0, dash).trim();
    final b = spec.substring(dash + 1).trim();
    int start, end;
    if (a.isEmpty) {
      final suffix = int.tryParse(b);
      if (suffix == null || suffix <= 0) return _badRange;
      start = max(0, size - suffix);
      end = size - 1;
    } else {
      final s = int.tryParse(a);
      if (s == null) return _badRange;
      start = s;
      end = b.isEmpty ? size - 1 : (int.tryParse(b) ?? -1);
      if (end >= size) end = size - 1;
    }
    if (start < 0 || start >= size || end < start) return _badRange;
    return (start, end);
  }

  static Stream<List<int>> _read(RandomAccessFile raf, int from, int length) async* {
    await raf.setPosition(from);
    var left = length;
    while (left > 0) {
      final chunk = await raf.read(min(_chunk, left));
      if (chunk.isEmpty) break;
      left -= chunk.length;
      yield chunk;
    }
  }

  // ───────────────────────── Helpers ─────────────────────────

  static Future<void> _html(HttpResponse res, String html) async {
    res.headers
      ..contentType = ContentType.html
      ..set('Content-Security-Policy',
          "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; media-src 'self'; frame-ancestors 'none'");
    res.write(html);
    await res.close();
  }

  static Future<void> _send(HttpResponse res, ContentType type, String body, {String? attachment}) async {
    res.headers.contentType = type;
    if (attachment != null) res.headers.set('Content-Disposition', 'attachment; filename="$attachment"');
    res.write(body);
    await res.close();
  }

  static Future<void> _redirect(HttpResponse res, String to) async {
    res.statusCode = HttpStatus.seeOther;
    res.headers.set(HttpHeaders.locationHeader, to);
    await res.close();
  }

  static Future<void> _status(HttpResponse res, int code) async {
    res.statusCode = code;
    await res.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
