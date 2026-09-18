# RecoverX

Android data-recovery app that finds hidden, renamed, and orphaned files using binary file signatures (magic numbers). Built with Flutter + your shared theme package.

## Requirements

- Flutter ≥ 3.24
- Android SDK 26 (min) / 35 (target)
- The shared theme package at `../theme` (GitHub: `its-ash/theme`)

## Get started

```sh
flutter pub get
dart run build_runner build --delete-conflicting-locks
flutter run
```

## Project structure

```
lib/
  main.dart
  domain/                  # Models
    file_signature.dart    # Signature model
    file_item.dart         # Recovered file model
    signature_database.dart# All magic-number definitions
  core/
    scanner/
      signature_matcher.dart   # Pure-Dart matcher engine
      scanner_service.dart     # Directory walk + scan
      scan_models.dart         # ScanMode + ScanProgress
    recovery/
      recovery_service.dart    # Copy + restore correct extension
    permissions/
      permission_handler.dart  # MANAGE_EXTERNAL_STORAGE + SAF + MediaStore
  data/
    scan_database.dart         # Drift database for results
  ui/
    app_shell.dart             # Bottom-nav shell
    theme/
      theme_controller.dart    # Light/dark/system
    home/
      home_screen.dart
      home_view_model.dart
    scan/
      scan_progress_screen.dart
      scan_view_model.dart
    results/
      results_screen.dart
      results_view_model.dart
      file_detail_sheet.dart
android/
  app/src/main/AndroidManifest.xml  # Permissions
```

## Scanning modes

| Mode | Description |
| --- | --- |
| Quick | Common media folders + known locations |
| Deep | Full storage including hidden and system directories |
| Signature-only | Ignore file names/extensions — match by magic numbers only |
| Hidden | Dotfiles and `.nomedia`-guarded files |

## Adding a new file signature

Open `lib/domain/signature_database.dart` and append a `FileSignature` entry. It is automatically picked up by every scanner — no other code changes needed.

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

Use `null` for wildcard bytes (versioned headers like AVI / MKV / MOV).

## Architecture

- **MVVM + Clean Architecture** — ViewModels via Riverpod `StateNotifierProvider`, use-cases in `core/`, models in `domain/`.
- **Riverpod** for state management and dependency injection.
- **WorkManager** for background scans (planned integration via `workmanager` package).
- **Drift** for persisted scan results (`recoverx_scan.db`).
- **Shared theme package** (`../theme`) for Material Design 3 theming, colors, typography, and component library.

## Storage access

- **Android ≤12**: requests `MANAGE_EXTERNAL_STORAGE` (All Files Access). The app opens system settings for the user to grant it — we cannot auto-grant it.
- **Android 13+**: requests granular `READ_MEDIA_IMAGES / VIDEOS / AUDIO` permissions.
- Fallbacks to MediaStore and Storage Access Framework are used where full access is denied.

## Important warnings

### Recovery of truly deleted files

RecoverX **cannot** recover files that the filesystem has already unlinked — that requires root access and raw block-level carving. What RecoverX *does* recover:

- Hidden files (dotfiles, `.nomedia`-guarded)
- Files with renamed or missing extensions
- Orphaned files in cache / system directories still on disk
- Files in app data folders not normally browsable

The home screen surfaces this warning to the user before scanning.

### Google Play policy considerations

- `MANAGE_EXTERNAL_STORAGE` is a restricted permission on Google Play. You must submit a Permissions Declaration Form justifying its use and pass the Play Console review. Distribution via direct APK sideload or alternative stores has no such restriction.
- The app must not access files unrelated to its stated purpose.
- If targeting Play Store distribution and you cannot justify All Files Access, drop to MediaStore + SAF only and remove the `MANAGE_EXTERNAL_STORAGE` permission. Deep scan will be limited but the signature engine still works on accessible files.