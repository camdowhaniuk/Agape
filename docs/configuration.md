# Configuration

## Runtime Env Vars

- `OPENAI_API_KEY` (required for AI)
  - Pass at run time: `flutter run --dart-define=OPENAI_API_KEY=sk-...`
  - The app reads this at startup in `AIService` and never stores it.

## Build/Tooling

- Flutter 3.22.0+ / Dart 3.9+
- iOS/macOS: run `pod install` after native dep changes

## Assets

- Bible assets
  - `assets/web/metadata.json` and optional `assets/web/books/*.json`
  - USFM with Words of Christ: `assets/web_woc/*.usfm`
  - Red‑letter metadata: `assets/redletter_ranges*.json`
- Logos: `assets/logo/`

Declare new assets under the `assets:` section in `pubspec.yaml`.

