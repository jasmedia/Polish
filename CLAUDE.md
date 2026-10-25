# CLAUDE.md

Context for AI coding agents working in this repo.

## What this is

Polish is a macOS menu bar app that fixes grammar, spelling and wrong-word mistakes in a Slack draft using Apple's **on-device** Foundation Model, then puts the corrected text back in place. Press a hotkey, review a diff in a floating panel, press Return to accept. Slack syntax (mentions, channels, emoji, links, code) must survive untouched.

- Spec (source of truth): https://claude.ai/artifact/1ibnjtHxYLnoH8yfenoM2U
- Build plan with phase checklists: https://claude.ai/artifact/Hqmz1ZXymNjqxRCAgCiyhM
- Local snapshots of both: `planning/spec.md`, `planning/plan.md` (git-ignored; may lag the live docs)
- **Keep the build plan current.** When a plan task is finished, tick it in the live plan doc in the same session, with a short note of what was done (file, count, score or decision). When a phase's exit check passes, tick its remaining items and add `Complete on <date>: <one-line result>` to the phase's intro line, before starting the next phase. Items not done stay unticked with a note on why or where they moved. The plan is a Claude Docs doc: edit it through the Claude Docs connector (read the doc, then `update` the checklist items), never by publishing the artifact.

**Current phase:** Phase 3 (MVP app) is built and in its week of daily Slack use (exit check). Phase 4 (v1.1) started alongside it on 2026-10-24: tones (FR-8) are in the app (`SettingsStore.tone`, Tab in the panel). Keep my tone and Concise use v1; Casual and Professional use the restyle prompt v2 (`Prompt.v2` = `prompts/v2.txt` + `prompts/v2-tones/casual.txt`, `professional.txt`; a test checks they match). `prompts/v2-tones/concise.txt` is a draft that still changes meaning. Restyle tones that merge lines are rewritten paragraph by paragraph, then line by line inside a paragraph that merges again (slow on long drafts). FR-12 (long drafts): the panel shows part-by-part progress from `Pipeline.polish(progress:)`; long-draft timings are in `eval/RESULTS.md`. Scores and next steps in `eval/RESULTS.md` (Phase 4); `polish-cli golden --tone T --tone-prompt prompts/v2.txt` + `eval/tones.py` score a change. Phase 2 (PolishCore engine) is complete: the Swift pipeline meets the Phase 1 targets within run-to-run noise. Its open items for prompt v2 (under-correction, words added to correct drafts such as `the standup`, `10 a.m.`) are in `eval/RESULTS.md`; `make eval-swift` + `eval/compare.py` score a change.

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
make eval-swift   # golden set through the Swift pipeline → eval/runs/*.jsonl (needs the model)
swift run --package-path Packages/PolishCore polish-cli rewrite "..."  # one draft through PolishCore
fm respond "..."  # try a prompt against the on-device model (macOS 27)
```

There is **no Xcode project**. The app is a SwiftPM executable (`Package.swift`, sources in `App/Sources`) that `scripts/bundle.sh` wraps into `Polish.app` with `App/Info.plist` and signs with `App/Polish.entitlements`. Don't add an `.xcodeproj` or XcodeGen back.

## Layout

| Path | Contents |
| --- | --- |
| `Package.swift` | App executable target `Polish` + `PolishTests` |
| `App/Sources/` | SwiftUI/AppKit app: menu bar, later hotkey, text bridge, review panel |
| `App/Info.plist`, `App/Polish.entitlements` | Literal values (no Xcode build variables). Bundle ID `com.jasmedia.polish` |
| `Packages/PolishCore/` | UI-free engine: protector, chunker, rewriter, validator, differ. All model calls live here (`FoundationModelBackend`; tests use a scripted `RewriteModel`) |
| `Packages/PolishCore/Sources/PolishCLI/` | `polish-cli`: golden-set harness (writes the same columns as `eval/run.py`) and one-off rewrites |
| `eval/` | Python evaluation with `apple-fm-sdk` (uv project, macOS only) |
| `golden/golden.jsonl` | Golden test set shared by Python and Swift evals; schema in `golden/README.md` |
| `prompts/` | Versioned model instructions; `{tone}` and `{placeholders}` are template slots. `{placeholders}` gets the placeholder rule (naming each `⟦Tn⟧`, plus a keep-at-start line when the draft opens with a placeholder) only when the draft has placeholders; otherwise the model invents `⟦T1⟧`. Rule texts: `PLACEHOLDER_RULE`, `LEADING_MENTION_RULE`, `LEADING_RULE` in `eval/run.py`, mirrored in `InstructionsBuilder` (PolishCore); `Prompt.v1` must equal `prompts/v1.txt` and `Prompt.v2` the v2 files (tests check) |
| `scripts/` | `bundle.sh`, `run.sh`, `bootstrap.sh` |

## Rewrite pipeline (PolishCore)

1. **Normalize** whitespace, keep list markers.
2. **Protect** Slack tokens, mentions and personal-dictionary words → placeholders `⟦T1⟧`, `⟦T2⟧`… plus a map. Code blocks collapse to one placeholder. Record the draft's apostrophe style.
3. **Budget** tokens with `SystemLanguageModel.tokenCount(for:)` against `contextSize`: input budget = (0.7 × context − instructions − schema) / 2.6. Chunk on paragraph, then sentence boundaries (`NLTokenizer` plus end punctuation, since drafts often start sentences lowercase) when over it.
4. **Generate** with a new `LanguageModelSession` per request, temperature 0.2, `maximumResponseTokens` capped (≈ input chars / 2 + 200). Guided generation into `RewriteWithMistakes { mistakes: [String] (max 10), text: String }`: listing mistakes first keeps the model from editing correct text; the list itself is not used.
5. **Validate**: every placeholder exactly once, no merged or dropped lines (non-blank line count ≥ input's), length between −40% and +60% of the input (Concise: down to −60%), non-empty. On failure retry once at temperature 0, then return the original (per chunk). A context overflow re-splits the chunk at half the budget once, then fails with `PolishError.tooLong`.
6. **Restore**: put lines back into the draft's blank-line layout, undo expansions of contractions and `doc`/`config`/`repo` the draft used, convert quotes to the recorded style, restore placeholders, rejoin chunks, word-level diff for the panel.

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
- macOS 27 throws `LanguageModelError`; `PolishError(modelError:)` also maps the deprecated `LanguageModelSession.GenerationError` (hence one deprecation warning).
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

**Mentions:** the Slack composer carries mentions as display names (`@Alex Morgan`), not `<@U123>`, Protect them in this order:
1. **Rich pasteboard first.** After ⌘C, read Slack's HTML pasteboard type, take mention spans from its markup, protect each as one placeholder, and paste back HTML with those spans unchanged so the mentions stay linked. Whether Slack's markup marks mentions is unverified; not needed while plain-text paste keeps mentions linked (4).
2. **Plain-text fallback.** Protect `@` plus up to three following Title Case words (`@Alex Morgan Lee`), stopping at punctuation, a lowercase word (`@Alex can you…` protects `@Alex`), or a common sentence-start word such as `We`, `I`, `Can`, `Please`, `The` (`@Sam We can…` protects `@Sam`). Over-protecting is preferred to splitting a name. `@here`, `@channel` and `@everyone` are always single tokens.
3. **Personal dictionary overrides.** Dictionary names match exactly, for cases like `@de la Cruz`.
4. **Plain-text paste keeps mentions.** Checked in Slack desktop on 2026-10-24: pasting `@Athul` back as plain text leaves it a linked mention, so the review panel shows no warning. Revisit if a name stops re-linking (for example, two people with the same display name).

**Apostrophes:** keep the user's style. Detect straight (`'`) vs curly (`’`) in the draft (default straight when there are none) and convert the model's output to match after Restore, in code, not in the prompt. Placeholders (code, links) are never converted. Golden scoring compares quotes loosely except on rows tagged `apostrophe`.

## Repo

GitHub: `jasmedia/Polish` (public). Remote uses the SSH alias `github.com-personal`. CI: GitHub Actions on `runs-on: xcode-27`.
