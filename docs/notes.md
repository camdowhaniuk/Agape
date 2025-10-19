# Notes Feature Guide

The Notes screen recreates the Apple Notes browsing experience with Flutter.
This document explains the moving parts, how to extend them, and which tests
protect the existing behavior.

## UI Composition

- The screen uses a `CustomScrollView` with a `SliverAppBar.large` header.
- A gradient background blends the current theme surface colors for depth.
- Notes are grouped into sections rendered by `NotesSectionList`, wrapped in
  pill-shaped cards with soft dividers.
- Pinned notes appear in a compact capsule list above the chronological
  sections.
- The bottom search/compose bar slides and fades out when scrolling down and
  reappears as users scroll up.

## State Flow

```
NotesService (ValueNotifier<List<Note>>)
        │
        ├──> _notesNotifier (full list)
        └──> _applyFilter()
                │
                ├──> _pinnedNotes (ValueNotifier<List<Note>>)
                └──> _groupedNotes (ValueNotifier<Map<String,List<Note>>>)
```

- `_syncNotesFromService()` keeps the local notifiers aligned with the singleton
  `NotesService`.
- `_applyFilter()` runs after search input changes, pin/unpin toggles, deletes,
  and undo operations to refresh pinned and grouped collections simultaneously.

## Scroll-Driven Chrome

- A shared `ScrollController` feeds `_handleScrollDirectionChanged()` which
  toggles `_showNavChrome`.
- The screen informs the app shell via `widget.onScrollVisibilityChange`, so the
  bottom navigation bar hides in sync with the local search bar.
- Pulling past the `SliverAppBar` stretch trigger focuses the search field,
  enabling quick searches without tapping the text box.

## Swipe Actions

- Each note row is wrapped in `Dismissible` with two directions:
  - Swipe right to pin/unpin (non-destructive, the dismissible is canceled).
  - Swipe left to delete (permanent, with snackbar undo).
- Undo restores the note through `NotesService.addNote` and immediately calls
  `_syncNotesFromService()` for a consistent UI state.

## Overflow Menu

The overflow menu exposes planned actions (gallery view, sorting, grouping,
attachments). Each item currently reports "coming soon" so future work can
replace the stubs with real dialogs or screens.

## Empty State

- When `_applyFilter()` yields zero pinned and zero grouped notes, the body
  replaces the list with an illustrated empty state that encourages creating or
  pinning notes.
- The header count always reflects the filtered results.

## Entry Points For Extension

- Update `NotesSectionList` if you need alternate layouts (e.g., grid view).
- Hook up a persistent store by swapping `NotesService` with a database-backed
  implementation; keep the `ValueNotifier` interface to avoid UI changes.
- Add view settings by wiring the overflow menu to Riverpod or inherited state.

## Tests

`test/notes_screen_test.dart` covers:

- Rendering pinned and grouped sections
- Search filtering
- Editor round trip
- Deletions, pin toggles, and the empty search state

Add new tests alongside this file whenever you expand behavior.
