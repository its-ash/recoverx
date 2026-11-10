# RecoverX — Instructions

## Project type
Flutter app (Dart 3.5+), Android-only, shared theme package at `../theme`. Built for recovery / forensic work: the scan must never write to the device being examined.

## Architecture
- MVVM + Clean Architecture, Riverpod for state and DI, Drift for the last-scan cache.
- `domain/`: models, no Flutter deps (`FileItem`, `FileType`, `FileMetadata`, `SignatureDatabase`).
- `core/analysis/`: pure-Dart engine, unit-tested with in-memory bytes.
  - `byte_source.dart`: random-access reads (file or memory). Never load whole files.
  - `file_type_detector.dart`: real type from bytes. Container formats (ISO-BMFF, RIFF, EBML, ZIP, OLE2, Ogg, TIFF) and weak signatures (BMP, MP3/AAC frames, MPEG-TS) are checked structurally here.
  - `metadata_extractor.dart` + `exif_reader.dart`: EXIF/GPS, MP4 atoms, ID3, PDF info, SQLite tables. Also `IntegrityChecker` (intact / truncated).
  - `carver.dart`: finds whole JPEG/PNG/GIF/WebP/WAV/AVI/PDF/MP4/HEIC files inside other files by walking each format's structure.
  - `file_analyzer.dart`: one path → items (the file + anything carved from it).
- `core/scanner/`: `ScannerService` runs index + analyze in a background isolate (pause/resume/cancel via a control port). `LocationClassifier` flags trash (`.trashed-*`, recycle bins, LOST.DIR), `.pending-*`, hidden, cache and renamed files and names the source app.
- `core/recovery/recovery_service.dart`: export in an isolate. Streams bytes (whole file or carved range), SHA-256 of source and re-hash of the copy, restores mtime, writes `manifest.csv` + `report.json`.
- `core/storage/storage_volumes.dart`: internal storage, other users, SD / USB-OTG volumes.
- `core/share/browse_server.dart`: "Browse on a computer". Read-only LAN HTTP server (dart:io) behind a 6-digit PIN + session cookie. Serves only scan-result items by id, streams with HTTP Range (carved ranges too). Page HTML in `browse_page.dart` (no CDN; insert device data with `textContent` only; video thumbnails are drawn in the browser from a seeked frame, never made or stored on the phone; `test/browse_page_test.dart` syntax-checks the script with Node).
- `core/sensitive/`: on-device sensitive-content check. `sensitive_checker.dart` is pure Dart (eligibility, RGBA → model input, frame max) with the model and pixel sources injected for tests. `nsfw_model.dart` wraps `tflite_flutter` (`IsolateInterpreter`), decodes photos in memory via `dart:ui`, and gets video frames from the `recoverx/media` channel (`VideoFrames.kt`, `MediaMetadataRetriever`, in memory). Model: `assets/models/` (GantMan nsfw_model MobileNetV2, MIT; see its README). Result: `SensitiveRating` on `FileItem.sensitive`, saved in the `sensitiveJson` column, shown in reports and the browse page.
- `ui/`: `home_shell.dart` (`UiShell` bottom nav: Home, Check, Computer, Settings; tab in `homeTabProvider`, `home_tab.dart`), `scan_page.dart` (Home), `results/` (`item_video.dart` plays whole-file videos in place), `export/`, `share/` (`computer_page.dart` + browse controller), `sensitive/` (`content_check_page.dart`, check controller, blur gate, reveal state), `settings/` (`settingsProvider` in SharedPreferences: deep scan, blur, sensitivity, frames per video, server port, stop server on leave), `scan/scan_view_model.dart`, `scan/scan_radar.dart`.
- Sensitivity: ratings store raw scores; `SensitiveThresholds.current` (set from Settings) decides the level everywhere. It is static, so pass it explicitly into isolates (see the export isolate).

## Adding a file type
- Fixed magic number: add a `FileType` to `FileTypes` and a `FileSignature` to `SignatureDatabase.all` (`lib/domain/signature_database.dart`). Use `null` for wildcard bytes.
- Shares a container with other types: add the sub-type check in `FileTypeDetector`.
- Add common alternate extensions to `FileType._aliases` so they are not flagged as renamed.
- Add a test in `test/analysis_test.dart` with a fixture from `test/fixtures.dart`.

## Rules
- Scanning is read-only. Do not copy, cache or write evidence during a scan. Previews read bytes into memory.
- Export only on user action; prefer a removable volume and warn when exporting to the source volume.
- Every exported file must be hash-verified and listed in the report.
- The browse server starts only on user action and never serves paths outside the scan results. Every whole-file download (`/file?download=1`) is SHA-256 hashed while sent and listed in the download log (`/downloads/report.json`, `/downloads/manifest.csv`). The log lives in memory and is served to the computer; nothing is written to the phone.
- The sensitive-content check runs only on user action, on the device, after the scan. It reads files and decodes them in memory; it never uploads or writes evidence. Flagged items are blurred until revealed. Present its result as a flag for review, never as a finding, and never as CSAM detection.

## Theme
- Use the shared `theme` package (`import 'package:theme/theme.dart'`) and its `Ui*` widgets. Read `../theme/COMPONENTS.md` first.
- Theme mode is controlled by `themeModeProvider` in `lib/ui/theme/theme_controller.dart` (set from the Settings tab).

## Permissions
- Android 11+: `MANAGE_EXTERNAL_STORAGE` (All files access) for a full scan.
- Android 8–10: `READ/WRITE_EXTERNAL_STORAGE`.
- Media-only (Android 13+ `READ_MEDIA_*`) is a limited fallback; the UI warns about it.
- `PermissionGate` in `main.dart` re-checks on app resume.

## Build
- `make run`: flutter run
- `make build`: generate drift code + build APK
- `make deploy`: Ash Store release (`store.mk`): bump version, build, commit, tag, push, GitHub release with `recoverx.apk`
- `flutter test`: engine, classifier and export tests

## Code style
- Latest Dart idioms, `const` where possible
- Prefer Riverpod providers over manual state
- No TODOs in committed code
- Generated files (`*.g.dart`) are gitignored; run `dart run build_runner build` after changing the Drift table

## Release (Ash Store)
- Published through the Ash Store kit: `store.json` (id `recoverx`), `store.mk`, `index.html` + `CNAME` (`recoverx.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub release with `recoverx.apk` → repo topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
