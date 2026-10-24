# Polish

On-device grammar fixer for macOS. Press a hotkey in Slack and your rough draft comes back with clean grammar and spelling, while @mentions, emoji, links and code stay untouched. Built in Swift on Apple's Foundation Models framework. Runs fully on device: no API keys, nothing leaves your Mac.

> Status: Phase 0 (project setup). Nothing usable yet.

## Requirements

- macOS 27 on Apple Silicon, with Apple Intelligence turned on
- Xcode 27 installed (for the Swift toolchain and macOS SDK; the IDE is optional)
- [uv](https://docs.astral.sh/uv/) for the Python evaluation tools

## Getting started

```bash
./scripts/bootstrap.sh     # runs tests, builds the app, sets up eval/, checks the model
make run                   # build, sign and launch .build/app/Polish.app
make help                  # all commands
```

The app is a SwiftPM executable that `scripts/bundle.sh` wraps into a signed `.app`; there is no Xcode project. Signing uses your Apple Development identity if one is in the keychain (override with `POLISH_SIGN_IDENTITY`), so the Accessibility permission survives rebuilds.

## Repository layout

| Path | What lives there |
| --- | --- |
| `App/` | macOS menu bar app target (SwiftUI + AppKit) and its tests |
| `Packages/PolishCore/` | UI-free Swift package with the rewrite pipeline: protector, chunker, rewriter, validator, differ |
| `eval/` | Python evaluation harness using Apple's Foundation Models SDK for Python |
| `golden/` | Golden test set (JSONL) used by both the Python and Swift evaluations |
| `prompts/` | Versioned model instructions |
| `scripts/` | `bundle.sh` (build + sign the .app), `run.sh`, `bootstrap.sh` |

## Tests

```bash
make test-core   # PolishCore engine tests
make test-app    # app tests
make test        # both
```

CI runs both on GitHub's `xcode-27` runners. The on-device model is not available on CI, so tests that need it skip themselves there and run only on a Mac with Apple Intelligence.

## Privacy

Polish uses only the on-device `SystemLanguageModel`. It makes no network calls, stores no text unless you turn on history, and logs message text only as private.

## License

MIT
