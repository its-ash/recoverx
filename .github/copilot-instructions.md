# RecoverX — Copilot Instructions

## Project type
Flutter app (Dart 3.5+), Android-only, shared theme package at `../theme`.

## Architecture
- MVVM + Clean Architecture
- Riverpod (`flutter_riverpod`) for state and DI
- Drift for local scan-result database
- `domain/` = models (no Flutter deps), `core/` = services/use-cases, `data/` = DB, `ui/` = screens + view models

## Theme
- Always use the shared `theme` package (`import 'package:theme/theme.dart'`)
- Do not define custom colors/typography — pull from `AppTheme.lightTheme()` / `AppTheme.darkTheme()`
- Theme mode (light/dark/system) is controlled by `themeModeProvider` in `lib/ui/theme/theme_controller.dart`

## Signature engine
- All file signatures live in `lib/domain/signature_database.dart`
- To add a new file type, append a `FileSignature` entry — no other code changes needed
- Use `null` bytes in `pattern` for wildcard positions (versioned headers)
- The matcher (`lib/core/scanner/signature_matcher.dart`) is pure Dart and unit-testable

## Scanning
- `ScannerService` reads only the first `SignatureDatabase.maxHeaderBytes` of each file — never loads whole files
- Supports pause / resume / cancel via stream controllers
- WorkManager integration for background scans lives in `core/scanner/` (planned)

## Permissions
- Android ≤12: `MANAGE_EXTERNAL_STORAGE` (user must grant in system settings)
- Android 13+: granular `READ_MEDIA_IMAGES/VIDEOS/AUDIO`
- Permission flow gated by `PermissionGate` in `main.dart`

## Recovery
- Recovered files go to `/RecoverX/Recovered/` under the external storage dir
- Extension is restored based on detected signature
- `RecoveryService` handles single + batch recovery

## Build
- `make run` — flutter run
- `make build` — generate drift code + build APK
- `make deploy` — commit + push to main

## Code style
- Latest Dart idioms, `const` where possible
- Prefer Riverpod providers over manual state
- No TODOs in committed code — finish the implementation
- Generated files (`*.g.dart`) are gitignored