# Agape

# Agape

Agape is a Flutter discipleship companion: read Scripture, capture highlights and notes, and chat with an AI mentor that keeps responses grounded in the Bible.

## Features

- **Bible study**: Hybrid offline-first Bible reader with red-letter support and chapter caching.
- **Notes**: Apple Notes-inspired board with pinning, grouped sections, stretch-to-search, and swipe actions covered by widget tests.
- **Highlights**: Persistent verse highlights with shared color palettes (see `lib/services/highlight_service.dart`).
- **AI mentor**: Chat powered by the OpenAI Chat Completions API (`gpt-4o` by default) with local conversation storage.
- **Multi-platform**: Flutter targets iOS, Android, macOS, Windows, and Linux with platform-specific runners scaffolded.

## Architecture Overview

- **State**: Primarily local stateful widgets, with Riverpod available for future expansion.
- **Services layer**: `lib/services/` contains Bible loading/caching, notes persistence, highlight utilities, and AI client abstractions.
- **UI modules**: Screens live in `lib/screens/`, widgets in `lib/widgets/`, and models in `lib/models/`.
- **Assets**: Scripture metadata and content under `assets/web/`, logo variations in `assets/logo/`, and red-letter metadata in `assets/redletter_ranges*.json`.
- See `docs/architecture.md` for diagrams and deeper explanations.

## Getting Started

### Prerequisites

- Flutter 3.22.0+ with the Dart 3.9 SDK
- Xcode (for iOS) or Android Studio (for Android) if you plan to run on devices
- OpenAI API key with access to `gpt-4o` (or adjust the model in `lib/services/ai_service.dart`)

### Setup

```bash
git clone https://github.com/<your-org>/agape.git
cd agape
flutter pub get
```

Provide the OpenAI key when running:

```bash
flutter run --dart-define=OPENAI_API_KEY=sk-...
```

For iOS, run `cd ios && pod install` if native dependencies change.

### Useful Commands

- Launch on a specific device: `flutter run -d ios`
- Hot restart: press `r` in the running terminal session
- Generate launcher icons: `flutter pub run flutter_launcher_icons`

## Quality Gates

- Format: `dart format .`
- Lints: `dart analyze`
- Tests: `flutter test` (includes extensive coverage for the Notes experience in `test/notes_screen_test.dart`)

Failing any of these should block a PR.

## Documentation

- Repository cleanup checklist: `docs/repository_cleanup.md`
- Architecture overview: `docs/architecture.md`
- Notes feature specifics: `docs/notes.md`
- Contribution guidelines: `CONTRIBUTING.md`

### Specs and Roadmap

- v1 Spec (product + technical): `docs/v1_spec.md`
- Testing plan: `docs/testing.md`
- Roadmap and backlog: `docs/roadmap.md`
- Configuration and env vars: `docs/configuration.md`

Keep documentation updated when you introduce new features or workflows.

## Maintenance

- Before pushing, follow the steps in `docs/repository_cleanup.md` to remove generated artifacts, rerun formatting/lints, and confirm tests pass.
- Rotate API keys and secrets regularly; do not commit them to the repo. Use `--dart-define` or CI secrets.

## License

This project is currently private (`publish_to: none`). Add licensing details here when ready to publish.
