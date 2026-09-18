import 'file_signature.dart';

/// Central, easily-extendable database of file signatures.
///
/// To add a new type: append a [FileSignature] entry to [_signatures] and it is
/// automatically picked up by every scanner.
class SignatureDatabase {
  SignatureDatabase._();

  static final List<FileSignature> _signatures = [
    // ───────────────────────── Images ─────────────────────────
    FileSignature(
      id: 'jpeg',
      category: FileCategory.image,
      extension: 'jpg',
      mimeType: 'image/jpeg',
      displayName: 'JPEG Image',
      pattern: [0xFF, 0xD8, 0xFF],
      footer: [0xFF, 0xD9],
    ),
    FileSignature(
      id: 'png',
      category: FileCategory.image,
      extension: 'png',
      mimeType: 'image/png',
      displayName: 'PNG Image',
      pattern: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      footer: [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82],
    ),
    FileSignature(
      id: 'gif87',
      category: FileCategory.image,
      extension: 'gif',
      mimeType: 'image/gif',
      displayName: 'GIF Image',
      pattern: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],
    ),
    FileSignature(
      id: 'gif89',
      category: FileCategory.image,
      extension: 'gif',
      mimeType: 'image/gif',
      displayName: 'GIF Image',
      pattern: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
    ),
    FileSignature(
      id: 'webp',
      category: FileCategory.image,
      extension: 'webp',
      mimeType: 'image/webp',
      displayName: 'WEBP Image',
      pattern: [0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x57, 0x45, 0x42, 0x50],
    ),
    FileSignature(
      id: 'bmp',
      category: FileCategory.image,
      extension: 'bmp',
      mimeType: 'image/bmp',
      displayName: 'Bitmap Image',
      pattern: [0x42, 0x4D],
    ),
    FileSignature(
      id: 'heic',
      category: FileCategory.image,
      extension: 'heic',
      mimeType: 'image/heic',
      displayName: 'HEIC Image',
      pattern: [0x00, 0x00, 0x00, 0x24, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63],
      offset: 4,
      maxHeaderBytes: 16,
    ),

    // ───────────────────────── Videos ─────────────────────────
    FileSignature(
      id: 'mp4',
      category: FileCategory.video,
      extension: 'mp4',
      mimeType: 'video/mp4',
      displayName: 'MP4 Video',
      pattern: [0x00, 0x00, 0x00, null, 0x66, 0x74, 0x79, 0x70],
      offset: 4,
      maxHeaderBytes: 12,
    ),
    FileSignature(
      id: 'mov',
      category: FileCategory.video,
      extension: 'mov',
      mimeType: 'video/quicktime',
      displayName: 'QuickTime Video',
      pattern: [0x00, 0x00, 0x00, null, 0x6D, 0x6F, 0x6F, 0x76],
      offset: 4,
      maxHeaderBytes: 12,
    ),
    FileSignature(
      id: 'avi',
      category: FileCategory.video,
      extension: 'avi',
      mimeType: 'video/x-msvideo',
      displayName: 'AVI Video',
      pattern: [0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x41, 0x56, 0x49, 0x20],
    ),
    FileSignature(
      id: 'mkv',
      category: FileCategory.video,
      extension: 'mkv',
      mimeType: 'video/x-matroska',
      displayName: 'Matroska Video',
      pattern: [0x1A, 0x45, 0xDF, 0xA3],
    ),
    FileSignature(
      id: '3gp',
      category: FileCategory.video,
      extension: '3gp',
      mimeType: 'video/3gpp',
      displayName: '3GP Video',
      pattern: [0x00, 0x00, 0x00, null, 0x66, 0x74, 0x79, 0x70, 0x33, 0x67, 0x70],
      offset: 4,
      maxHeaderBytes: 12,
    ),
    FileSignature(
      id: 'webm',
      category: FileCategory.video,
      extension: 'webm',
      mimeType: 'video/webm',
      displayName: 'WEBM Video',
      pattern: [0x1A, 0x45, 0xDF, 0xA3],
    ),

    // ───────────────────────── Audio ───────────────────────────
    FileSignature(
      id: 'mp3',
      category: FileCategory.audio,
      extension: 'mp3',
      mimeType: 'audio/mpeg',
      displayName: 'MP3 Audio',
      pattern: [0x49, 0x44, 0x33], // ID3
      maxHeaderBytes: 3,
    ),
    FileSignature(
      id: 'mp3_ff',
      category: FileCategory.audio,
      extension: 'mp3',
      mimeType: 'audio/mpeg',
      displayName: 'MP3 Audio',
      pattern: [0xFF, 0xFB],
      maxHeaderBytes: 2,
    ),
    FileSignature(
      id: 'aac',
      category: FileCategory.audio,
      extension: 'aac',
      mimeType: 'audio/aac',
      displayName: 'AAC Audio',
      pattern: [0xFF, 0xF1],
      maxHeaderBytes: 2,
    ),
    FileSignature(
      id: 'wav',
      category: FileCategory.audio,
      extension: 'wav',
      mimeType: 'audio/wav',
      displayName: 'WAV Audio',
      pattern: [0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x57, 0x41, 0x56, 0x45],
    ),
    FileSignature(
      id: 'ogg',
      category: FileCategory.audio,
      extension: 'ogg',
      mimeType: 'audio/ogg',
      displayName: 'OGG Audio',
      pattern: [0x4F, 0x67, 0x67, 0x53],
      maxHeaderBytes: 4,
    ),
    FileSignature(
      id: 'flac',
      category: FileCategory.audio,
      extension: 'flac',
      mimeType: 'audio/flac',
      displayName: 'FLAC Audio',
      pattern: [0x66, 0x4C, 0x61, 0x43],
      maxHeaderBytes: 4,
    ),

    // ───────────────────────── Documents ───────────────────────
    FileSignature(
      id: 'pdf',
      category: FileCategory.document,
      extension: 'pdf',
      mimeType: 'application/pdf',
      displayName: 'PDF Document',
      pattern: [0x25, 0x50, 0x44, 0x46, 0x2D],
      maxHeaderBytes: 5,
    ),
    FileSignature(
      id: 'doc',
      category: FileCategory.document,
      extension: 'doc',
      mimeType: 'application/msword',
      displayName: 'Word Document',
      pattern: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
      maxHeaderBytes: 8,
    ),
    FileSignature(
      id: 'docx',
      category: FileCategory.document,
      extension: 'docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      displayName: 'Word Document',
      pattern: [0x50, 0x4B, 0x03, 0x04],
      maxHeaderBytes: 4,
    ),
    FileSignature(
      id: 'ppt',
      category: FileCategory.document,
      extension: 'ppt',
      mimeType: 'application/vnd.ms-powerpoint',
      displayName: 'PowerPoint Document',
      pattern: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
      maxHeaderBytes: 8,
    ),
    FileSignature(
      id: 'pptx',
      category: FileCategory.document,
      extension: 'pptx',
      mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      displayName: 'PowerPoint Document',
      pattern: [0x50, 0x4B, 0x03, 0x04],
      maxHeaderBytes: 4,
    ),
    FileSignature(
      id: 'xls',
      category: FileCategory.document,
      extension: 'xls',
      mimeType: 'application/vnd.ms-excel',
      displayName: 'Excel Document',
      pattern: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
      maxHeaderBytes: 8,
    ),
    FileSignature(
      id: 'xlsx',
      category: FileCategory.document,
      extension: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      displayName: 'Excel Document',
      pattern: [0x50, 0x4B, 0x03, 0x04],
      maxHeaderBytes: 4,
    ),

    // ───────────────────────── Archives ────────────────────────
    FileSignature(
      id: 'zip',
      category: FileCategory.archive,
      extension: 'zip',
      mimeType: 'application/zip',
      displayName: 'ZIP Archive',
      pattern: [0x50, 0x4B, 0x03, 0x04],
      maxHeaderBytes: 4,
    ),
    FileSignature(
      id: 'rar4',
      category: FileCategory.archive,
      extension: 'rar',
      mimeType: 'application/vnd.rar',
      displayName: 'RAR Archive',
      pattern: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00],
      maxHeaderBytes: 7,
    ),
    FileSignature(
      id: 'rar5',
      category: FileCategory.archive,
      extension: 'rar',
      mimeType: 'application/vnd.rar',
      displayName: 'RAR Archive',
      pattern: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00],
      maxHeaderBytes: 8,
    ),
    FileSignature(
      id: '7z',
      category: FileCategory.archive,
      extension: '7z',
      mimeType: 'application/x-7z-compressed',
      displayName: '7Z Archive',
      pattern: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
      maxHeaderBytes: 6,
    ),
    FileSignature(
      id: 'apk',
      category: FileCategory.archive,
      extension: 'apk',
      mimeType: 'application/vnd.android.package-archive',
      displayName: 'Android Package',
      pattern: [0x50, 0x4B, 0x03, 0x04],
      maxHeaderBytes: 4,
    ),
  ];

  /// Ordered list — more specific signatures (longer patterns) first so
  /// ambiguous short headers (e.g. ZIP vs DOCX) are disambiguated where
  /// possible.
  static List<FileSignature> get all =>
      List.unmodifiable(_signatures);

  /// Max header bytes any signature needs to read.
  static int get maxHeaderBytes =>
      _signatures.fold(0, (m, s) => m > s.maxHeaderBytes ? m : s.maxHeaderBytes);

  /// Signatures filtered to a single category.
  static List<FileSignature> forCategory(FileCategory c) =>
      _signatures.where((s) => s.category == c).toList();
}