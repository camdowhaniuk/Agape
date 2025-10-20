# Agape v1 Product + Technical Spec

## Vision

Agape is a discipleship companion: read Scripture, capture insights, and chat with a Christ‑centered AI mentor grounded in the Bible. v1 focuses on fast, offline‑first Scripture reading, delightful notes, and a safe, useful AI assistant.

## Goals

- Fast, reliable Bible reading with offline cache and red‑letter support.
- Notes that feel as smooth as Apple Notes with search, pinning, and simple editing.
- AI chat that prefers Scripture, can open verses, and stays within an orthodox lens.
- Cross‑platform polish (iOS, Android, desktop) with consistent navigation.

## Non‑Goals (v1)

- Cloud sync/multi‑device accounts (stubbed for later via Supabase).
- Audio Bible and commentary libraries.
- Social/sharing feed.
- Advanced editor/attachments beyond plain text.

## Personas

- Daily Reader: Wants quick navigation, highlights, and verse lookup.
- Note‑Taker: Captures reflections and organizes with pins and folders.
- Seeker: Asks questions; expects clear, biblical answers with references.

## Key Flows and Acceptance Criteria

### Navigation

- Tabs: Home, Bible, Agape (AI), Notes, More.
- Bottom bar hides on scroll down within Bible/AI/Notes and reappears on scroll up.
- Switching tabs resets the hide/show “arming” state; AI tab activation scrolls to bottom.

### Bible

- Books list with chapter picker; default opens last location.
- Chapter rendering via `ScrollablePositionedList` with headings and verse numbers.
- Data sources: assets JSON/USFM → documents cache → `bible-api.com` fallback.
- Red‑letter: words of Christ highlighted using USFM + `redletter_ranges*.json`.
- Highlights: long‑press and drag to select text within a verse range, choose a color, and persist. Edit/remove from overflow.
- Jump: tap a reference (from AI/note) to open `BibleScreen` at the book/chapter/verse.
- Persistence: last visible book/chapter/verse remembered (`UserStateService`).

Acceptance
- Opens default to last location; first‑run opens John 1.
- Navigating to another book/chapter animates and restores scroll position.
- Red‑letter displays consistently for all four Gospels and Acts quotes.
- Highlights list shows most‑recent first in More → Highlights.

### Notes

- Grouped list by Today, Yesterday, This Week, or Month Year.
- Pinned section appears if any notes are pinned; swipe right toggles pin; swipe left deletes with undo.
- Search filters across title and preview; empty state when no results.
- Compose: new note starts blank with cursor in body; back saves draft to list.
- Editor: single plain‑text field; first line becomes title; next line preview.

Acceptance
- Search updates pinned and grouped sections live.
- Pinning/unpinning updates counts and section visibility without flicker.
- Delete shows snackbar with Undo; Undo restores in place.
- Returning from editor updates title/preview and is searchable.

### AI (Agape)

- Conversations persisted locally; latest appears first.
- System prompt anchors tone and doctrine; model defaults to `gpt-4o`.
- Composer: multiline, send button when non‑empty; scroll to bottom on send.
- Scripture references in messages render as tappable pills; tapping opens Bible at the reference.
- Grounding: model instructed to prefer Scripture and cite naturally; do not hallucinate obscure doctrines.

Acceptance
- Missing API key shows clear instruction to pass `--dart-define=OPENAI_API_KEY=...`.
- Network errors display a friendly retry message.
- References like “John 15:1–5; 7” parse and link correctly.
- Switching tabs preserves scroll and composer state.

### More

- Highlights list with remove/edit color actions.
- Dark mode toggle persists for session.
- Stubs for Downloads and Account.

Acceptance
- Removing or recoloring a highlight updates Bible view and list next open.

## Information Architecture

- Screens: `lib/screens/` (home, bible, ai, notes, more, highlights, editor).
- Services: `lib/services/` (bible, highlights, notes, AI, conversation store, user state, USFM utils).
- Models: `lib/models/` (`Note`, `VerseHighlight`).
- Widgets: `lib/widgets/` (logo, markdown message, notes list, pills).
- Utils: `lib/utils/` (scripture reference parsing, highlight colors).

## Data Model

- Note: id, title, preview, createdAt, updatedAt?, folder?, tags[], pinned.
- VerseHighlight: colorId, start, end, excerpt?, createdAt?; keyed by book|chapter|verse.
- AIConversation: id, title, messages[], createdAt, updatedAt (stored in SharedPreferences JSON).
- Bible Cache: per book/chapter JSON under documents dir `web_cache/`.
- User State: last opened book/chapter/verse; last highlight color.

## Integrations

- OpenAI Chat Completions API via `AIService`.
- Bible content via bundled assets (JSON/USFM) and `bible-api.com` fallback.
- Future: Supabase for auth/sync (dependency present; not wired in v1).

## Security & Privacy

- API keys are provided at runtime via `--dart-define` and never persisted.
- No telemetry by default; add analytics only with explicit consent.
- Local storage only (SharedPreferences + app documents). Provide export/clear options in More.

## Accessibility

- Respect text scale factor and platform contrast settings.
- Minimum 44x44 tap targets; sufficient color contrast for highlights.
- Screen reader labels for nav, actions, and verse highlights.

## Performance Targets

- Bible chapter open < 300ms when cached, < 1.2s on first network fetch.
- Smooth 60fps scrolling with sticky headers and highlight overlays.
- AI message render < 50ms for typical responses.

## Internationalization

- Text isolated in widgets for future i18n; English only in v1.

## Error Handling

- Bible: asset/cached/network fallback order; toast/snackbar on fetch errors.
- AI: auth/network errors show friendly message without blocking conversation.
- Notes/Highlights: validate writes and show toasts on persistence issues.

## Implementation Plan (Remaining Work)

1) Bible polish
- Add book/chapter picker UI and deep‑link jumps.
- Persist last visible verse via `UserStateService` on scroll; restore precisely.
- Improve highlight selection handles and overflow UX; add long‑press to edit.

2) Notes persistence
- Replace in‑memory `NotesService` with local JSON or `shared_preferences` v2 storage while preserving the `ValueNotifier` API.
- Add basic editor screen with title/body split and autosave.

3) AI enhancements
- Link scripture references in `MarkdownMessage` using `ScriptureReferenceParser.extractMatches` and wrap with tappable chips.
- Add conversation list switcher (left column on desktop, overflow menu on mobile).
- Optional: streaming responses for better feel.

4) More/Settings
- Highlights screen: edit color inline; remove confirmation.
- Add “Export data” (notes + highlights JSON) and “Clear data” actions.
- Expose text size slider for Bible reading.

5) Home
- Recent notes, continue reading shortcut, and “Ask Agape” quick actions.

6) Testing
- Expand widget tests for Bible highlights, AI reference links, and nav hide/show behavior.

## Definition of Done

- Acceptance criteria above satisfied for Bible/Notes/AI/More.
- All new code covered by unit/widget tests where practical.
- `dart format`, `dart analyze`, and `flutter test` pass cleanly.
- README and docs updated to reflect any changes.

## Open Questions

- Which translation(s) ship in v1 beyond WEB/USFM assets?
- Should we support a pure offline mode with pre‑download? How large?
- Any minimum OS versions or platform‑specific design tweaks?

