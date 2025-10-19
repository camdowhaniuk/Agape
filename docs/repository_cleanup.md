# Repository Cleanup Guide

Keep the project healthy by running this checklist whenever you prepare a release,
hand the repo to another contributor, or notice unexpected files in version
control.

## 1. Confirm Git Status

- `git status -sb`
- Ensure only intentional changes remain. Stash or commit WIP work.

## 2. Remove Generated Artifacts

- `flutter clean`
- Delete platform-specific build folders if they linger:
  - `rm -rf build ios/Flutter/Pods ios/.symlinks`
- If Xcode or Android Studio created derived data outside the project, clear it
  from the IDE as needed.

## 3. Restore Dependencies

- `flutter pub get`
- For iOS, run `pod install` from `ios/` after `flutter pub get` if you changed
  native dependencies.

## 4. Static Checks

- `dart format .`
- `dart analyze`

Resolve any issues flagged by the analyzer before proceeding.

## 5. Run Tests

- `flutter test`

Pay attention to the widget coverage around the Notes screen, which validates
pinning, counts, and empty-state rendering (`test/notes_screen_test.dart`).

## 6. Scan for Large or Accidental Files

- `git ls-files --others --exclude-standard`
- `git ls-tree --full-tree -r HEAD | sort -k4`

Delete or add `.gitignore` entries for generated assets, media dumps, or
temporary logs. The existing `.gitignore` already excludes `build/` and most
tooling output—add new patterns if you introduce other generators.

## 7. Final Validation

- Re-run `git status -sb` to verify the tree is clean.
- Tag or branch once the repository is tidy.

> Tip: for force cleaning everything untracked **and ignored**, use
> `git clean -fdX`, but only after double-checking you do not have local files
> you need to keep. This command is destructive.
