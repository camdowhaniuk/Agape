# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agape is a Flutter discipleship companion app that combines Bible reading, note-taking, highlight management, and AI-powered spiritual mentoring. The app is offline-first with multi-platform support (iOS, Android, macOS, Windows, Linux).

Key features:
- Hybrid offline-first Bible reader with red-letter support and chapter caching
- Apple Notes-inspired note interface with pinning, grouping, and search
- Persistent verse highlights with color palettes
- AI chat mentor powered by Google Gemini (free forever) with Scripture grounding
- Firebase authentication (email, Google, Facebook, Apple)

## Development Commands

### Setup
```bash
flutter pub get
cd ios && pod install  # iOS only, after native dependency changes
```

### Running the App
```bash
# Standard run
flutter run

# With Google Gemini API key (required for AI features)
# Get your free key at https://aistudio.google.com/apikey
flutter run --dart-define=GEMINI_API_KEY=your_key_here

# Specific device
flutter run -d ios
flutter run -d android
```

### Quality Gates
These must pass before any PR:
```bash
dart format .       # Format code
dart analyze        # Run lints
flutter test        # Run all tests
```

### Testing
```bash
flutter test                           # Run all tests
flutter test test/notes_screen_test.dart  # Run specific test file
```

### Asset Generation
```bash
flutter pub run flutter_launcher_icons  # Regenerate app icons
```

## Architecture

### Overall Structure
- **State Management**: Primarily local `StatefulWidget`s; Riverpod available but minimally used
- **Navigation**: Bottom tab bar with 5 screens (Home, Bible, AI/Agape, Notes, More)
- **Authentication**: Firebase Auth via `AuthGate` widget that routes between login/main shell

### Directory Layout
```
lib/
├── main.dart                 # Entry point, AgapeMainShell with nav
├── screens/                  # Main UI screens
│   ├── home_screen.dart
│   ├── bible_screen.dart
│   ├── ai_screen.dart
│   ├── notes_screen.dart
│   ├── more_screen.dart
│   ├── highlights_screen.dart
│   ├── login_screen.dart
│   └── register_screen.dart
├── services/                 # Business logic layer
│   ├── bible_service.dart          # 3-tier fetch: USFM assets → cached JSON → bible-api.com
│   ├── highlight_service.dart      # Verse highlight persistence via SharedPreferences
│   ├── notes_service.dart          # Note CRUD with ValueNotifier
│   ├── ai_service.dart             # Google Gemini API wrapper (free forever)
│   ├── ai_conversation.dart        # Conversation model
│   ├── ai_conversation_store.dart  # Local conversation persistence
│   ├── user_state_service.dart     # Last Bible location, settings
│   ├── auth_service.dart           # Firebase auth helpers
│   └── usfm_utils.dart             # USFM parsing utilities
├── models/                   # Data models
│   ├── highlight.dart        # VerseHighlight model
│   └── note.dart
├── widgets/                  # Reusable UI components
│   └── auth_gate.dart        # Routes to login or main shell
└── utils/
    ├── highlight_colors.dart        # Shared color palette
    └── scripture_reference.dart     # Parse/extract verse references from text
```

### Key Architectural Patterns

**Bible Content Loading (3-tier hybrid)**
1. First tries USFM assets in `assets/web_woc/` for exact red-letter text
2. Falls back to bundled JSON in `assets/web/books/`
3. Finally fetches from `bible-api.com` and caches to app documents at `web_cache/<Book>/<chapter>.json`
4. Red-letter ranges loaded from `assets/redletter_ranges*.json` and merged on startup

**Scripture Reference Linking**
- AI messages and notes can contain verse references (e.g., "John 15:1-5")
- `ScriptureReferenceParser` in `utils/scripture_reference.dart` extracts these
- Tappable pills rendered via `MarkdownMessage` widget
- Tapping opens `BibleScreen` at the specified book/chapter/verse

**Bottom Bar Auto-Hide**
- `BibleScreen`, `AIScreen`, and `NotesScreen` track scroll direction
- Call `onScrollVisibilityChange(false)` when scrolling down, `true` when up
- Switching tabs resets visibility via `_navVisibilityResetTick`
- AI tab activation increments `_aiActivationTick` to scroll chat to bottom

**Highlights**
- Long-press text in `BibleScreen` to select verse range and pick color
- Stored in `SharedPreferences` by `HighlightService` keyed as `<book>|<chapter>|<verse>`
- Edit/remove from More → Highlights screen
- Tapping a highlight navigates to its Bible location

## Configuration & Environment

### Required Runtime Variables
- `GEMINI_API_KEY`: Optional, for AI chat features
  - Get your free key at https://aistudio.google.com/apikey (no credit card required)
  - Pass via `--dart-define=GEMINI_API_KEY=your_key_here`
  - Used by `AIService` (lib/services/ai_service.dart:20)
  - Never persisted; purely runtime
  - **Cost**: Free forever (up to 1,000 requests/day)

### Firebase Setup
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`
- macOS: `macos/Runner/GoogleService-Info.plist`
- Config generated via FlutterFire CLI; see `lib/firebase_options.dart`

### Assets
All assets must be declared in `pubspec.yaml`:
- Bible metadata: `assets/web/metadata.json`
- Book content: `assets/web/books/*.json`
- USFM with red letters: `assets/web_woc/*.usfm`
- Red-letter ranges: `assets/redletter_ranges*.json`
- Logos: `assets/logo/`, `assets/agape_logo.png`

## Testing Strategy

Widget tests are the primary test type (see `test/notes_screen_test.dart` for extensive coverage of Notes features).

Test files:
- `test/notes_screen_test.dart`: Pin, unpin, delete, undo, search, grouping
- `test/ai_screen_scroll_test.dart`: Auto-scroll behavior
- `test/scripture_reference_parser_test.dart`: Verse reference extraction
- `test/markdown_message_test.dart`: Message rendering
- `test/ai_conversation_store_test.dart`: Conversation persistence

Run single test file with:
```bash
flutter test test/notes_screen_test.dart
```

## AI System Prompt & Grounding

The AI mentor uses a system prompt (defined in `AIScreen`) that:
- Anchors responses in orthodox Christian theology
- Prefers Scripture citations and naturally includes verse references
- Avoids hallucinating obscure doctrines
- Keeps tone warm and pastoral

When the model responds with verse references (e.g., "John 15:1-5"), they are automatically parsed and rendered as tappable pills that open the Bible to that location.

## Data Persistence

- **Bible cache**: `<app-docs>/web_cache/<Book>/<chapter>.json`
- **Highlights**: `SharedPreferences` with keys like `highlights_<book>|<chapter>|<verse>`
- **Notes**: In-memory via `NotesService` (ValueNotifier-based)
- **AI conversations**: `SharedPreferences` JSON via `AIConversationStore`
- **User state**: Last Bible location stored via `UserStateService`

No cloud sync in v1; all data is local-only.

## Common Development Tasks

### Adding a new Bible translation
1. Add USFM or JSON files to `assets/web_woc/` or `assets/web/books/`
2. Update `assets/web/metadata.json` with book list and chapter counts
3. Declare new assets in `pubspec.yaml`
4. Optionally pass `translationId` to `BibleService` constructor

### Adding a new screen
1. Create screen file in `lib/screens/`
2. Add to `screens` list in `_AgapeMainShellState.build()` in `lib/main.dart`
3. Update `_NavBarItem` list if adding a new tab

### Modifying AI behavior
- System prompt is defined at the top of `AIScreen.build()` method
- Model/temperature controlled in `AIService` constructor (lib/services/ai_service.dart:16)
- To switch providers, replace implementation of `AIService.reply()` method

### Testing new features
- Widget tests preferred over integration tests
- See `test/notes_screen_test.dart` for patterns: pump, find, tap, verify
- Mock services when needed (see how `NotesService` is injected)

## Important Constraints & Conventions

- **API keys**: Never commit. Always use `--dart-define` or CI secrets
- **Offline-first**: Bible content should work without network after first fetch
- **Performance targets**:
  - Chapter load < 300ms when cached
  - 60fps scrolling with highlights
  - AI response render < 50ms
- **Accessibility**: Minimum 44x44 tap targets, respect text scaling
- **Red-letter text**: Only applies to four Gospels + Acts quotes; uses `\wj` tags in USFM
- **Navigation state**: `_showBottomBar`, `_aiActivationTick`, `_navVisibilityResetTick` in main.dart control complex nav behaviors

## Spec & Roadmap Documents

For detailed feature requirements and future plans, see:
- `docs/v1_spec.md` - Product + technical spec with acceptance criteria
- `docs/roadmap.md` - Feature backlog and priorities
- `docs/testing.md` - Testing plan and coverage goals
- `docs/configuration.md` - Environment variables and asset setup
- `docs/notes.md` - Notes feature details
- `docs/architecture.md` - Deeper architecture diagrams/explanations

## Before Committing

Follow the checklist in `docs/repository_cleanup.md`:
1. Remove generated artifacts
2. Run `dart format .`
3. Run `dart analyze` (must pass)
4. Run `flutter test` (must pass)
5. Update relevant docs if you changed workflows
