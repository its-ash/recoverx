import 'file_signature.dart';

/// Every file type RecoverX can report.
class FileTypes {
  FileTypes._();

  static const _i = FileCategory.image;
  static const _v = FileCategory.video;
  static const _a = FileCategory.audio;
  static const _d = FileCategory.document;
  static const _z = FileCategory.archive;
  static const _x = FileCategory.data;

  // ── Images ──
  static const jpeg =
      FileType(id: 'jpeg', category: _i, extension: 'jpg', mimeType: 'image/jpeg', displayName: 'JPEG Image');
  static const png =
      FileType(id: 'png', category: _i, extension: 'png', mimeType: 'image/png', displayName: 'PNG Image');
  static const gif =
      FileType(id: 'gif', category: _i, extension: 'gif', mimeType: 'image/gif', displayName: 'GIF Image');
  static const webp =
      FileType(id: 'webp', category: _i, extension: 'webp', mimeType: 'image/webp', displayName: 'WebP Image');
  static const bmp =
      FileType(id: 'bmp', category: _i, extension: 'bmp', mimeType: 'image/bmp', displayName: 'Bitmap Image');
  static const tiff =
      FileType(id: 'tiff', category: _i, extension: 'tif', mimeType: 'image/tiff', displayName: 'TIFF Image');
  static const dng =
      FileType(id: 'dng', category: _i, extension: 'dng', mimeType: 'image/x-adobe-dng', displayName: 'DNG RAW Photo');
  static const cr2 = FileType(
      id: 'cr2', category: _i, extension: 'cr2', mimeType: 'image/x-canon-cr2', displayName: 'Canon RAW Photo');
  static const nef = FileType(
      id: 'nef', category: _i, extension: 'nef', mimeType: 'image/x-nikon-nef', displayName: 'Nikon RAW Photo');
  static const arw =
      FileType(id: 'arw', category: _i, extension: 'arw', mimeType: 'image/x-sony-arw', displayName: 'Sony RAW Photo');
  static const raf = FileType(
      id: 'raf', category: _i, extension: 'raf', mimeType: 'image/x-fuji-raf', displayName: 'Fujifilm RAW Photo');
  static const heic =
      FileType(id: 'heic', category: _i, extension: 'heic', mimeType: 'image/heic', displayName: 'HEIC Image');
  static const heif =
      FileType(id: 'heif', category: _i, extension: 'heif', mimeType: 'image/heif', displayName: 'HEIF Image');
  static const avif =
      FileType(id: 'avif', category: _i, extension: 'avif', mimeType: 'image/avif', displayName: 'AVIF Image');
  static const psd = FileType(
      id: 'psd', category: _i, extension: 'psd', mimeType: 'image/vnd.adobe.photoshop', displayName: 'Photoshop Image');

  // ── Videos ──
  static const mp4 =
      FileType(id: 'mp4', category: _v, extension: 'mp4', mimeType: 'video/mp4', displayName: 'MP4 Video');
  static const m4v =
      FileType(id: 'm4v', category: _v, extension: 'm4v', mimeType: 'video/x-m4v', displayName: 'M4V Video');
  static const mov =
      FileType(id: 'mov', category: _v, extension: 'mov', mimeType: 'video/quicktime', displayName: 'QuickTime Video');
  static const threeGp =
      FileType(id: '3gp', category: _v, extension: '3gp', mimeType: 'video/3gpp', displayName: '3GP Video');
  static const threeG2 =
      FileType(id: '3g2', category: _v, extension: '3g2', mimeType: 'video/3gpp2', displayName: '3G2 Video');
  static const mkv =
      FileType(id: 'mkv', category: _v, extension: 'mkv', mimeType: 'video/x-matroska', displayName: 'Matroska Video');
  static const webm =
      FileType(id: 'webm', category: _v, extension: 'webm', mimeType: 'video/webm', displayName: 'WebM Video');
  static const avi =
      FileType(id: 'avi', category: _v, extension: 'avi', mimeType: 'video/x-msvideo', displayName: 'AVI Video');
  static const flv =
      FileType(id: 'flv', category: _v, extension: 'flv', mimeType: 'video/x-flv', displayName: 'Flash Video');
  static const asf =
      FileType(id: 'asf', category: _v, extension: 'wmv', mimeType: 'video/x-ms-asf', displayName: 'Windows Media');
  static const mpeg =
      FileType(id: 'mpeg', category: _v, extension: 'mpg', mimeType: 'video/mpeg', displayName: 'MPEG Video');
  static const mpegTs =
      FileType(id: 'ts', category: _v, extension: 'ts', mimeType: 'video/mp2t', displayName: 'MPEG-TS Video');

  // ── Audio ──
  static const mp3 =
      FileType(id: 'mp3', category: _a, extension: 'mp3', mimeType: 'audio/mpeg', displayName: 'MP3 Audio');
  static const aac =
      FileType(id: 'aac', category: _a, extension: 'aac', mimeType: 'audio/aac', displayName: 'AAC Audio');
  static const m4a =
      FileType(id: 'm4a', category: _a, extension: 'm4a', mimeType: 'audio/mp4', displayName: 'M4A Audio');
  static const wav =
      FileType(id: 'wav', category: _a, extension: 'wav', mimeType: 'audio/wav', displayName: 'WAV Audio');
  static const ogg =
      FileType(id: 'ogg', category: _a, extension: 'ogg', mimeType: 'audio/ogg', displayName: 'Ogg Vorbis Audio');
  static const opus =
      FileType(id: 'opus', category: _a, extension: 'opus', mimeType: 'audio/opus', displayName: 'Opus Audio');
  static const flac =
      FileType(id: 'flac', category: _a, extension: 'flac', mimeType: 'audio/flac', displayName: 'FLAC Audio');
  static const amr =
      FileType(id: 'amr', category: _a, extension: 'amr', mimeType: 'audio/amr', displayName: 'AMR Voice Recording');
  static const awb = FileType(
      id: 'awb', category: _a, extension: 'awb', mimeType: 'audio/amr-wb', displayName: 'AMR-WB Voice Recording');
  static const midi =
      FileType(id: 'midi', category: _a, extension: 'mid', mimeType: 'audio/midi', displayName: 'MIDI Audio');
  static const aiff =
      FileType(id: 'aiff', category: _a, extension: 'aiff', mimeType: 'audio/aiff', displayName: 'AIFF Audio');

  // ── Documents ──
  static const pdf =
      FileType(id: 'pdf', category: _d, extension: 'pdf', mimeType: 'application/pdf', displayName: 'PDF Document');
  static const doc = FileType(
      id: 'doc', category: _d, extension: 'doc', mimeType: 'application/msword', displayName: 'Word 97-2003 Document');
  static const xls = FileType(
      id: 'xls',
      category: _d,
      extension: 'xls',
      mimeType: 'application/vnd.ms-excel',
      displayName: 'Excel 97-2003 Workbook');
  static const ppt = FileType(
      id: 'ppt',
      category: _d,
      extension: 'ppt',
      mimeType: 'application/vnd.ms-powerpoint',
      displayName: 'PowerPoint 97-2003');
  static const msg = FileType(
      id: 'msg',
      category: _d,
      extension: 'msg',
      mimeType: 'application/vnd.ms-outlook',
      displayName: 'Outlook Message');
  static const ole = FileType(
      id: 'ole',
      category: _d,
      extension: 'ole',
      mimeType: 'application/x-ole-storage',
      displayName: 'Office 97-2003 File');
  static const docx = FileType(
      id: 'docx',
      category: _d,
      extension: 'docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      displayName: 'Word Document');
  static const xlsx = FileType(
      id: 'xlsx',
      category: _d,
      extension: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      displayName: 'Excel Workbook');
  static const pptx = FileType(
      id: 'pptx',
      category: _d,
      extension: 'pptx',
      mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      displayName: 'PowerPoint Presentation');
  static const odt = FileType(
      id: 'odt',
      category: _d,
      extension: 'odt',
      mimeType: 'application/vnd.oasis.opendocument.text',
      displayName: 'OpenDocument Text');
  static const ods = FileType(
      id: 'ods',
      category: _d,
      extension: 'ods',
      mimeType: 'application/vnd.oasis.opendocument.spreadsheet',
      displayName: 'OpenDocument Spreadsheet');
  static const odp = FileType(
      id: 'odp',
      category: _d,
      extension: 'odp',
      mimeType: 'application/vnd.oasis.opendocument.presentation',
      displayName: 'OpenDocument Presentation');
  static const epub =
      FileType(id: 'epub', category: _d, extension: 'epub', mimeType: 'application/epub+zip', displayName: 'EPUB Book');
  static const rtf = FileType(
      id: 'rtf', category: _d, extension: 'rtf', mimeType: 'application/rtf', displayName: 'Rich Text Document');

  // ── Archives ──
  static const zip =
      FileType(id: 'zip', category: _z, extension: 'zip', mimeType: 'application/zip', displayName: 'ZIP Archive');
  static const apk = FileType(
      id: 'apk',
      category: _z,
      extension: 'apk',
      mimeType: 'application/vnd.android.package-archive',
      displayName: 'Android App (APK)');
  static const jar = FileType(
      id: 'jar', category: _z, extension: 'jar', mimeType: 'application/java-archive', displayName: 'Java Archive');
  static const rar =
      FileType(id: 'rar', category: _z, extension: 'rar', mimeType: 'application/vnd.rar', displayName: 'RAR Archive');
  static const sevenZip = FileType(
      id: '7z', category: _z, extension: '7z', mimeType: 'application/x-7z-compressed', displayName: '7-Zip Archive');
  static const gzip =
      FileType(id: 'gzip', category: _z, extension: 'gz', mimeType: 'application/gzip', displayName: 'GZIP Archive');
  static const bzip2 = FileType(
      id: 'bzip2', category: _z, extension: 'bz2', mimeType: 'application/x-bzip2', displayName: 'BZIP2 Archive');
  static const xz =
      FileType(id: 'xz', category: _z, extension: 'xz', mimeType: 'application/x-xz', displayName: 'XZ Archive');
  static const tar =
      FileType(id: 'tar', category: _z, extension: 'tar', mimeType: 'application/x-tar', displayName: 'TAR Archive');

  // ── Data ──
  static const sqlite = FileType(
      id: 'sqlite', category: _x, extension: 'db', mimeType: 'application/vnd.sqlite3', displayName: 'SQLite Database');
  static const vcf =
      FileType(id: 'vcf', category: _x, extension: 'vcf', mimeType: 'text/vcard', displayName: 'Contacts (vCard)');
  static const ics =
      FileType(id: 'ics', category: _x, extension: 'ics', mimeType: 'text/calendar', displayName: 'Calendar (iCal)');

  static const List<FileType> all = [
    jpeg, png, gif, webp, bmp, tiff, dng, cr2, nef, arw, raf, heic, heif, avif, psd, //
    mp4, m4v, mov, threeGp, threeG2, mkv, webm, avi, flv, asf, mpeg, mpegTs, //
    mp3, aac, m4a, wav, ogg, opus, flac, amr, awb, midi, aiff, //
    pdf, doc, xls, ppt, msg, ole, docx, xlsx, pptx, odt, ods, odp, epub, rtf, //
    zip, apk, jar, rar, sevenZip, gzip, bzip2, xz, tar, //
    sqlite, vcf, ics,
  ];

  static final Map<String, FileType> _byId = {for (final t in all) t.id: t};

  static FileType? byId(String id) => _byId[id];
}

/// Plain magic-number signatures. Container formats are handled in code by
/// `FileTypeDetector`.
///
/// To add a type with a fixed magic number: add a [FileType] above and a
/// [FileSignature] here. Nothing else needs to change.
class SignatureDatabase {
  SignatureDatabase._();

  static List<int> _ascii(String s) => s.codeUnits;

  static final List<FileSignature> all = List.unmodifiable([
    const FileSignature(type: FileTypes.png, pattern: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    FileSignature(type: FileTypes.gif, pattern: _ascii('GIF87a')),
    FileSignature(type: FileTypes.gif, pattern: _ascii('GIF89a')),
    FileSignature(type: FileTypes.psd, pattern: [..._ascii('8BPS'), 0x00, 0x01]),
    FileSignature(type: FileTypes.raf, pattern: _ascii('FUJIFILMCCD-RAW')),
    FileSignature(type: FileTypes.flv, pattern: [..._ascii('FLV'), 0x01]),
    const FileSignature(
        type: FileTypes.asf,
        pattern: [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C]),
    const FileSignature(type: FileTypes.mpeg, pattern: [0x00, 0x00, 0x01, 0xBA]),
    FileSignature(type: FileTypes.flac, pattern: _ascii('fLaC')),
    FileSignature(type: FileTypes.amr, pattern: _ascii('#!AMR\n')),
    FileSignature(type: FileTypes.awb, pattern: _ascii('#!AMR-WB\n')),
    FileSignature(type: FileTypes.midi, pattern: [..._ascii('MThd'), 0x00, 0x00, 0x00, 0x06]),
    FileSignature(type: FileTypes.aiff, pattern: [..._ascii('FORM'), null, null, null, null, ..._ascii('AIFF')]),
    FileSignature(type: FileTypes.aiff, pattern: [..._ascii('FORM'), null, null, null, null, ..._ascii('AIFC')]),
    FileSignature(type: FileTypes.pdf, pattern: _ascii('%PDF-')),
    FileSignature(type: FileTypes.rtf, pattern: _ascii(r'{\rtf')),
    const FileSignature(type: FileTypes.rar, pattern: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]),
    const FileSignature(type: FileTypes.rar, pattern: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]),
    const FileSignature(type: FileTypes.sevenZip, pattern: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]),
    const FileSignature(type: FileTypes.gzip, pattern: [0x1F, 0x8B, 0x08]),
    FileSignature(type: FileTypes.bzip2, pattern: [..._ascii('BZh'), null, 0x31, 0x41, 0x59, 0x26, 0x53, 0x59]),
    const FileSignature(type: FileTypes.xz, pattern: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]),
    FileSignature(type: FileTypes.tar, pattern: _ascii('ustar'), offset: 257),
    FileSignature(type: FileTypes.sqlite, pattern: [..._ascii('SQLite format 3'), 0x00]),
    FileSignature(type: FileTypes.vcf, pattern: _ascii('BEGIN:VCARD')),
    FileSignature(type: FileTypes.ics, pattern: _ascii('BEGIN:VCALENDAR')),
  ]);

  /// Bytes the detector must read to test every plain signature.
  static final int headerBytes = all.fold(0, (m, s) => m > s.headerBytes ? m : s.headerBytes);
}
