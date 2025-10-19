# Contributing to Agape

Thank you for investing in Agape. This guide explains how to propose changes,
keep the codebase healthy, and collaborate smoothly.

## Before You Start

- Install Flutter 3.22.0+ and Dart 3.9+.
- Run `flutter doctor` to ensure your environment is green.
- Review the architecture (`docs/architecture.md`) and feature guides (`docs/notes.md`).

## Development Workflow

1. Fork the repository (or create a feature branch if you have direct access).
2. Create a descriptive branch name, e.g. `feature/notes-sort-dialog` or `fix/bible-cache`.
3. Run `flutter pub get`.
4. Implement your changes with tests and documentation updates as needed.

## Code Style & Quality

- Format everything: `dart format .`
- Lint before committing: `dart analyze`
- Run the test suite: `flutter test`
- Keep imports ordered (use `dart fix --apply` if needed).
- Prefer descriptive variable and method names; add concise comments only when
  the intent is not obvious.

## Commit Guidelines

- Write clear, present-tense commit messages: `Add gallery view toggle`.
- Avoid committing generated artifacts (`build/`, `.dart_tool/`, etc.).
- Squash fix-up commits before opening a pull request if possible.

## Pull Request Checklist

- [ ] Tests pass locally (`flutter test`)
- [ ] Lints pass locally (`dart analyze`)
- [ ] Formatting applied (`dart format .`)
- [ ] Documentation updated (README, `docs/`, or code comments)
- [ ] Screenshots or recordings attached for major UI changes
- [ ] Linked issue reference in the PR description (if applicable)

## Documentation Expectations

- Update `README.md` with new features or configuration flags.
- Add or modify guides under `docs/` to reflect architectural changes.
- Use `docs/repository_cleanup.md` before posting a PR to keep the repo clean.

## Reporting Issues

Open a GitHub issue with:

- Summary of the problem
- Steps to reproduce
- Observed vs expected behavior
- Logs or screenshots if relevant

Security issues or API key leaks should be reported privately to the maintainer.

## Questions?

Feel free to start a discussion or ping the maintainers through the repository
issue tracker. We are grateful for your contributions!
