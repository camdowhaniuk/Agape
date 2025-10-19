# Architecture Overview

## High-Level Structure

```
lib/
 ├─ main.dart                // App bootstrap, theme, root navigation shell
 ├─ models/                  // Immutable data models (e.g., Note)
 ├─ screens/                 // Feature screens (Home, Bible, AI, Notes, etc.)
 ├─ services/                // Domain services and data access layers
 ├─ utils/                   // Helpers such as scripture reference parsing
 └─ widgets/                 // Reusable UI building blocks
```

The app uses Flutter 3 with Material 3 widgets. State is primarily managed with
stateful widgets and `ValueNotifier`s; Riverpod is in `pubspec.yaml` for future
expansion but not widely adopted yet.

## Navigation Shell

`lib/main.dart` hosts `AgapeApp`, a `StatefulWidget` that:

- Maintains the active tab index across five primary screens.
- Controls the bottom navigation bar visibility with `_showBottomBar`.
- Forwards navigation visibility signals to tabs (`BibleScreen`, `AIScreen`,
  `NotesScreen`) via constructors (`onScrollVisibilityChange`,
  `navVisible`, and `navVisibilityResetTick`).
- Applies a shared color scheme and supports dark/light mode toggling via the
  "More" tab.

## Feature Modules

### Bible Screen

`BibleScreen` renders Scripture via a `ScrollablePositionedList`, loading
chapters from `BibleService`. Highlights are sourced from `HighlightService`
and can be stored with color identifiers. The screen listens to scroll events to
hide the navigation chrome once the user scrolls down, mirroring the behavior
of the Notes and AI screens.

### Notes Screen

`NotesScreen` presents journal entries grouped by display date. It uses:

- `NotesService` (see below) for persistence and in-memory updates.
- A custom `NotesSectionList` widget to mimic Apple Notes styling.
- Scroll listeners and a stretchable `SliverAppBar` to hide the nav bar and
  focus the search field.
- `ValueListenableBuilder` wrappers to rebuild when notes or pin states change.

Design details and extension points are documented in `docs/notes.md`.

### AI Screen

`AIScreen` manages chat sessions with the AI mentor:

- `AIService` wraps the OpenAI Chat Completions API (default model
  `gpt-4o`) and handles error cases, auth, and response parsing.
- `AIConversationStore` persists conversations to local storage.
- Scroll and focus management keeps the composer visible while respecting the
  global navigation visibility contract.

## Services Layer

### BibleService

- Hybrid content loading: attempts to read bundled JSON under `assets/web/`,
  falls back to `bible-api.com`, and caches responses in the app documents
  directory for offline use.
- Provides red-letter lookup via precomputed assets (`assets/redletter_ranges*`).

### NotesService

- Stores notes in memory using a singleton `ValueNotifier<List<Note>>`.
- Offers CRUD methods (`createEmptyNote`, `togglePinned`, `deleteNote`) and
  utilities (`groupNotesByDisplayDate`) to group by human-readable sections.
- Exposes `notesListenable` for UI layers to subscribe and react immediately.

### HighlightService

- Manages highlight colors and persistence for scripture passages.
- Integrates with `UserStateService` to remember the last viewed book/chapter.

### AIService

- Thin HTTP client around the OpenAI API.
- Handles missing API keys, non-200 responses, and parsing of chat choices.
- Supports dependency injection of `http.Client` for testing.

## Assets & Data

- Bible metadata lives under `assets/web/metadata.json` and `assets/web/books/`.
- Logos and concepts reside in `assets/logo/`.
- Red-letter metadata (`assets/redletter_ranges*.json`) identifies verses spoken
  by Jesus.
- Add new assets by listing them in `pubspec.yaml` under the `assets` section.

## Testing Strategy

- Unit tests live beside services and utilities where applicable.
- Widget tests cover major flows:
  - `test/notes_screen_test.dart` validates pinning, deletions, search empty
    states, and nav visibility syncing.
  - `test/ai_screen_scroll_test.dart` verifies chat scroll ergonomics.
  - Additional coverage exists for markdown rendering and conversation storage.

Run `flutter test` before submitting changes.

## Extending The App

- Add new tabs by updating `AgapeApp` and `_IOSNavBar`.
- Introduce Riverpod providers in `lib/providers/` (create if needed) for more
  complex state without refactoring existing widgets immediately.
- For additional AI models, adjust the `model` parameter in `AIService` and
  document access requirements.
- Keep documentation under `docs/` aligned with code changes so future
  contributors understand design decisions.
