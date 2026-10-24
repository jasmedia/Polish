# CLAUDE.md

Context for AI coding agents working in this repo.

## What this is

Polish is a macOS menu bar app that fixes grammar, spelling and wrong-word mistakes in a Slack draft using Apple's **on-device** Foundation Model, then puts the corrected text back in place. Press a hotkey, review a diff in a floating panel, press Return to accept. Slack syntax (mentions, channels, emoji, links, code) must survive untouched.

- Spec (source of truth): https://claude.ai/artifact/1ibnjtHxYLnoH8yfenoM2U
- Build plan with phase checklists: https://claude.ai/artifact/Hqmz1ZXymNjqxRCAgCiyhM
- Local snapshots of both: `planning/spec.md`, `planning/plan.md` (git-ignored; may lag the live docs)

**Current phase:** Phase 0 (setup) is done: the menu bar app runs and shows model status. Next is Phase 1, the prompt spike: build the golden set, prototype placeholder protection in Python, and tune `prompts/v1.txt` with `fm` and the Python SDK.

## Commands

```bash
make run          # build, sign, relaunch .build/app/Polish.app
make test         # PolishCore + app tests
make test-core    # swift test --package-path Packages/PolishCore
make test-app     # swift test (root package)
make app          # bundle only; CONFIG=release make app for release
make logs         # log stream for subsystem com.jasmedia.polish
make eval-setup   # uv sync --project eval
make check-model  # fm + Python SDK smoke test
fm respond "..."  # try a prompt against the on-device model (macOS 27)
```

There is **no Xcode project**. The app is a SwiftPM executable (`Package.swift`, sources in `App/Sources`) that `scripts/bundle.sh` wraps into `Polish.app` with `App/Info.plist` and signs with `App/Polish.entitlements`. Don't add an `.xcodeproj` or XcodeGen back.

## Layout

| Path | Contents |
| --- | --- |
| `Package.swift` | App executable target `Polish` + `PolishTests` |
| `App/Sources/` | SwiftUI/AppKit app: menu bar, later hotkey, text bridge, review panel |
| `App/Info.plist`, `App/Polish.entitlements` | Literal values (no Xcode build variables). Bundle ID `com.jasmedia.polish` |
| `Packages/PolishCore/` | UI-free engine: protector, chunker, rewriter, validator, differ. All model calls live here |
| `eval/` | Python evaluation with `apple-fm-sdk` (uv project, macOS only) |
| `golden/golden.jsonl` | Golden test set shared by Python and Swift evals; schema in `golden/README.md` |
| `prompts/` | Versioned model instructions; `{tone}` is a template slot |
| `scripts/` | `bundle.sh`, `run.sh`, `bootstrap.sh` |

## Rewrite pipeline (PolishCore)

1. **Normalize** whitespace, keep list markers.
2. **Protect** Slack tokens and personal-dictionary words → placeholders `⟦T1⟧`, `⟦T2⟧`… plus a map. Code blocks collapse to one placeholder.
3. **Budget** tokens with `SystemLanguageModel.tokenUsage(for:)` against `contextSize`; chunk on paragraph, then sentence boundaries if over ~70%.
4. **Generate** with a new `LanguageModelSession` per request, guided generation into a `@Generable` type, temperature 0.2.
5. **Validate**: every placeholder exactly once, length between −40% and +60% of the input (Concise: down to −60%), non-empty. On failure retry once at temperature 0, then return the original.
6. **Restore** placeholders, rejoin chunks, word-level diff for the panel.

The model never sees raw Slack syntax. Placeholder integrity is enforced by validation, never trusted to the model.

## Rules

- **On-device only.** Use `SystemLanguageModel` only. No Private Cloud Compute, no network calls, no network entitlement, no analytics.
- **Never log message text in clear.** Use `Log.engine` / `Log.bridge` / `Log.ui` from PolishCore, with `privacy: .private` for any user text. Timings, token counts and error codes may be `.public`.
- **Never modify the user's text on any error path.** Errors show a message; the original stays.
- **Don't hard-code the context size** (8,192 tokens on macOS 27; it differs by OS version). Read `contextSize` at runtime.
- **Rewrite level matches ChatGPT**: clear, professional English, with rephrasing, expanded shorthand ("org" → "organization") and paragraph splits allowed; meaning, facts, names and requests never change. Golden `expected` values follow this style; rows tagged `reference` are real drafts with their ChatGPT rewrites.
- **US English** spelling in prompts, golden `expected` values and UI copy.
- **The repo is public**: anonymize anything built from real messages (names, products, links) before committing.
- Swift 6 language mode with strict concurrency; macOS 27+, Apple Silicon only. UI types are `@MainActor`; use `@Observable`, not `ObservableObject`.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- Tests that call the real model must skip when it's unavailable (CI has no Apple Intelligence):
  `@Suite(.enabled(if: ModelStatus.current().isReady, "On-device model not available"))`
- Keep PolishCore free of AppKit/SwiftUI so it stays testable from the CLI.
- Prompt changes go in a new `prompts/vN.txt` and must be scored on the golden set before they ship (Phase 1 sets the bar: ≥ 99% placeholder integrity, ≥ 95% unchanged-when-correct).

## Gotchas

- **Accessibility permission is tied to the code signature.** `bundle.sh` signs with the first Apple Development / Developer ID identity in the keychain (or `$POLISH_SIGN_IDENTITY`). Ad-hoc signing works but makes macOS forget the permission on every rebuild.
- **Not sandboxed by design**: cross-app Accessibility and synthetic ⌘A/⌘C/⌘V need it off. Distribution is Developer ID + notarization, not the App Store.
- `LSUIElement = YES`: no Dock icon or main window. UI is `MenuBarExtra`, a non-activating `NSPanel`, and a `Settings` scene.
- SwiftPM resource bundles from dependencies (e.g. KeyboardShortcuts in Phase 3) are copied into `Contents/Resources` by `bundle.sh`. Check `Bundle.module` loads after adding a package with resources.
- `apple-fm-sdk` builds against FoundationModels.framework and needs Xcode installed; `eval/pyproject.toml` restricts uv resolution to macOS.
- XML comments in plists can't contain `--`.

## Decisions (2026-10-24)

Review panel is always shown (no auto-replace); US spelling; ChatGPT-level rewriting, not minimal fixes; on-device model only; personal dictionary ships empty; name is Polish; MIT license.

**Open:** Slack composer text carries mentions as multi-word display names (`@Alex Morgan`), not `<@U123>`; how to protect them is undecided. Straight vs curly apostrophes is undecided (golden rows use straight).

## Repo

GitHub: `jasmedia/Polish` (public). Remote uses the SSH alias `github.com-personal`. CI: GitHub Actions on `runs-on: xcode-27`.
