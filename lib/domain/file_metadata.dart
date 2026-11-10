import 'dart:convert';

/// Whether the file's internal structure is complete.
enum Integrity {
  /// The format's end marker / index was found where expected.
  intact,

  /// The file is cut short or its index is missing (partly overwritten,
  /// interrupted download or copy). Often still partly viewable.
  truncated,

  /// The format has no cheap structural check.
  unknown,
}

/// Metadata read from inside a file (EXIF, MP4 atoms, ID3, ...).
///
/// Every field is optional: formats and files differ in what they carry.
class FileMetadata {
  const FileMetadata({
    this.width,
    this.height,
    this.takenAt,
    this.cameraMake,
    this.cameraModel,
    this.software,
    this.latitude,
    this.longitude,
    this.duration,
    this.title,
    this.artist,
    this.extra = const {},
  });

  final int? width;
  final int? height;

  /// Capture / creation time stored inside the file (not the filesystem
  /// time, which changes on copy).
  final DateTime? takenAt;
  final String? cameraMake;
  final String? cameraModel;
  final String? software;
  final double? latitude;
  final double? longitude;
  final Duration? duration;
  final String? title;
  final String? artist;

  /// Format-specific fields shown as-is in the detail view and report.
  final Map<String, String> extra;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isEmpty =>
      width == null &&
      height == null &&
      takenAt == null &&
      cameraMake == null &&
      cameraModel == null &&
      software == null &&
      !hasLocation &&
      duration == null &&
      title == null &&
      artist == null &&
      extra.isEmpty;

  FileMetadata copyWith({
    int? width,
    int? height,
    DateTime? takenAt,
    String? cameraMake,
    String? cameraModel,
    String? software,
    double? latitude,
    double? longitude,
    Duration? duration,
    String? title,
    String? artist,
    Map<String, String>? extra,
  }) =>
      FileMetadata(
        width: width ?? this.width,
        height: height ?? this.height,
        takenAt: takenAt ?? this.takenAt,
        cameraMake: cameraMake ?? this.cameraMake,
        cameraModel: cameraModel ?? this.cameraModel,
        software: software ?? this.software,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        duration: duration ?? this.duration,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        extra: extra ?? this.extra,
      );

  /// Readable label/value pairs for UI and reports.
  Map<String, String> toDisplayMap() {
    String two(int n) => n.toString().padLeft(2, '0');
    return {
      if (width != null && height != null) 'Dimensions': '$width × $height',
      if (takenAt != null)
        'Captured': '${takenAt!.year}-${two(takenAt!.month)}-${two(takenAt!.day)} '
            '${two(takenAt!.hour)}:${two(takenAt!.minute)}:${two(takenAt!.second)}',
      if (cameraMake != null) 'Make': cameraMake!,
      if (cameraModel != null) 'Model': cameraModel!,
      if (software != null) 'Software': software!,
      if (hasLocation) 'GPS': '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
      if (duration != null) 'Duration': _fmtDuration(duration!),
      if (title != null) 'Title': title!,
      if (artist != null) 'Artist': artist!,
      ...extra,
    };
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (takenAt != null) 'takenAt': takenAt!.toIso8601String(),
        if (cameraMake != null) 'cameraMake': cameraMake,
        if (cameraModel != null) 'cameraModel': cameraModel,
        if (software != null) 'software': software,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory FileMetadata.fromJson(Map<String, dynamic> j) => FileMetadata(
        width: j['width'] as int?,
        height: j['height'] as int?,
        takenAt: j['takenAt'] == null ? null : DateTime.tryParse(j['takenAt'] as String),
        cameraMake: j['cameraMake'] as String?,
        cameraModel: j['cameraModel'] as String?,
        software: j['software'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        duration: j['durationMs'] == null ? null : Duration(milliseconds: j['durationMs'] as int),
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        extra: (j['extra'] as Map?)?.cast<String, String>() ?? const {},
      );

  String encode() => jsonEncode(toJson());

  static FileMetadata? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return FileMetadata.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
