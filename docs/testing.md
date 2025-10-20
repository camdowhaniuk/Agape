# Testing Plan

This document outlines automated and manual testing for Agape v1.

## Automated

- Unit tests
  - `ScriptureReferenceParser` parsing and linking edge cases
  - `HighlightService` CRUD, sorting, and legacy key compatibility
  - `AIConversationStore` create/upsert/migrate legacy, trimming logic
  - `BibleService` red‑letter mapping for representative chapters

- Widget tests
  - Notes screen: pin/unpin, delete with undo, search empty state, counts
  - AI screen: scroll‑to‑bottom behavior, composer focus hide/show nav
  - Bible screen: nav hide/show on scroll, jump to verse exactness (golden optional)
  - Markdown message: inline code, lists, scripture chip linking

- Commands
  - Format: `dart format .`
  - Analyze: `dart analyze`
  - Run tests: `flutter test`

## Manual QA

- Navigation
  - Bottom bar hides on down scroll and returns on up scroll across Bible/AI/Notes
  - Switching tabs preserves state; AI tab activation scrolls to bottom

- Bible
  - Open default to last location; verify USFM red‑letter for John, Matthew
  - Highlight selection across verse segments; edit/remove actions
  - Network offline: cached chapters still render

- Notes
  - Create note; back saves draft; appears under the correct group
  - Swipe to pin and delete with undo; counts adjust
  - Search filters both pinned and grouped sections

- AI
  - Missing key path shows guidance; with key, responses render
  - References in replies turn into chips; tapping opens Bible at reference
  - Long conversation remains performant; no jank at bottom

- More
  - Highlights list reflects changes made in Bible; recolor/remove works
  - Dark mode toggle; check contrast for highlight colors

## Performance

- Target 60fps scrolling through long chapters
- Chapter open latency: <300ms cached, <1.2s first load on LTE
- Conversation append latency: <50ms render for 2–3k characters

## Accessibility

- Screen reader labels on nav items and action buttons
- Text scale 1.6x: no clipped text; controls remain tappable
- Contrast check on highlight palette in light/dark themes

