# AGENTS.md: instructions for coding agents in this repository

## What this is
Hazir: a personal budget app for Android (Flutter), later with an AI agent. Single user, all data on the phone.

Read before any work:
1. `docs/superpowers/specs/2026-11-25-budget-app-design.md` (the design, source of truth for WHAT)
2. The current plan in `docs/superpowers/plans/` (source of truth for HOW, task by task)

If the plan and the design disagree, stop and ask. Do not guess.

## How to work
- Work on ONE task of the plan at a time, only the task you are asked to do.
- Follow the task's steps in order: write the failing test, run it and see it fail, implement, run it and see it pass, commit.
- Use exactly the file paths, class names, function names and signatures in the task's Interfaces block. Later tasks depend on them.
- After finishing a task: run `flutter test` (whole suite) and `flutter analyze`. Both must be clean before committing.
- Tick the task's checkboxes in the plan file (`- [ ]` to `- [x]`) and commit with the message given in the task.
- At the end, report: what you did, test results, anything you could not do or had to decide yourself.
- The plan header mentions "superpowers" sub-skills. Those are for another tool; ignore that line and simply follow the steps.

## App name
The app's display name is "Hazir" (Android label in AndroidManifest and MaterialApp title). The Flutter project name stays `budget_app`.

## Hard rules (never break)
- Money is stored as integers in minor units (fen, paisa, cent). Never use `double` for money. Exchange rates use the `decimal` package.
- Every account has one currency. Transactions keep their original currency and are never rewritten.
- Transfers are never counted as spending or income.
- Never download fonts at runtime (no `google_fonts` package). Fonts are bundled assets.
- No secrets or API keys in source code.
- UI copy: sentence case, no all-caps labels, no middle-dot separators like "A · B".
- Colors only from `lib/ui/theme/app_colors.dart`. Brass `#E8B83A` is only a fill, with ink `#15201B` on top, never a text color.

## Environment notes (developer is in mainland China)
- Use the Flutter China mirrors if downloads fail:
  `PUB_HOSTED_URL=https://pub.flutter-io.cn` and `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- If Gradle cannot reach `google()` or `mavenCentral()`, tell the developer instead of changing build files on your own.

## Commands
- Tests: `flutter test`
- Analyze: `flutter analyze`
- Code generation (Drift): `dart run build_runner build --delete-conflicting-outputs`
- Debug APK: `flutter build apk --debug`
