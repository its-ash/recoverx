# RecoverX

Find hidden, renamed and orphaned files by their signature.

**[Website](https://recoverx.itsash.in)** · **[Download APK](https://github.com/its-ash/recoverx/releases/latest/download/recoverx.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Signature scanning**: identifies files by their binary signature (magic
  numbers), not their name. 30+ signatures across five categories:

  | Category | Formats |
  | --- | --- |
  | Images | JPEG, PNG, GIF, WEBP, BMP, HEIC |
  | Videos | MP4, MOV, AVI, MKV, 3GP, WEBM |
  | Audio | MP3, AAC, WAV, OGG, FLAC |
  | Documents | PDF, DOC, DOCX, PPT, PPTX, XLS, XLSX |
  | Archives | ZIP, RAR4, RAR5, 7Z, APK |

- **Scan modes**:

  | Mode | Description |
  | --- | --- |
  | Quick | Common media folders + known locations |
  | Deep | Full storage including hidden and system directories |
  | Signature-only | Ignore file names/extensions; match by magic numbers only |
  | Hidden | Dotfiles and `.nomedia`-guarded files |

- **Export** with hash-verified reports, and a browse server for a computer on
  the same network.

### What it can and cannot recover

RecoverX **cannot** recover files that the filesystem has already unlinked;
that needs root and raw block-level carving. It *does* find:

- hidden files (dotfiles, `.nomedia`-guarded);
- files with renamed or missing extensions;
- orphaned files in cache or system folders still on disk;
- files in app data folders not normally browsable.

The home screen shows this warning before a scan.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update RecoverX from it.
- **APK**: download the [latest APK](https://github.com/its-ash/recoverx/releases/latest/download/recoverx.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

Requires Android 8.0 (API 26) or later, arm64.

**Storage access**: Android 11+ asks for "All files access"
(`MANAGE_EXTERNAL_STORAGE`) for a full scan; you grant it in system settings.
Android 13+ media-only permissions are a limited fallback, and MediaStore and
the Storage Access Framework are used where full access is denied.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs

make run      # flutter run
make build    # generate drift code + release APK (arm64)
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

### Add a file signature

Append a `FileSignature` to `lib/domain/signature_database.dart`. Every scanner
picks it up. Use `null` for wildcard bytes (versioned headers like AVI, MKV, MOV).

```dart
FileSignature(
  id: 'webp',
  category: FileCategory.image,
  extension: 'webp',
  mimeType: 'image/webp',
  displayName: 'WEBP Image',
  pattern: [0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x57, 0x45, 0x42, 0x50],
)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `recoverx.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

```
lib/
  main.dart
  domain/          # models + signature_database.dart (all magic numbers)
  core/
    scanner/       # signature matcher, directory walk + scan, scan models
    recovery/      # copy + restore correct extension
    permissions/   # MANAGE_EXTERNAL_STORAGE + SAF + MediaStore
    share/         # browse server for a computer on the same network
  data/            # Drift database for results
  ui/              # app shell, theme controller, home, scan, results
```

MVVM + Clean Architecture with Riverpod, Drift for scan results, and the shared
theme package for UI.

**Google Play note**: `MANAGE_EXTERNAL_STORAGE` is restricted on Google Play
and needs a Permissions Declaration. Direct APK and Ash Store installs have no
such restriction.

## License

No license file is included yet.

Built by [itsash.in](https://itsash.in).
