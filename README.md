# Polish

On-device grammar fixer for macOS. Press a hotkey in Slack and your rough draft comes back with clean grammar and spelling, while @mentions, emoji, links and code stay untouched. Built in Swift on Apple's Foundation Models framework. Runs fully on device: no API keys, nothing leaves your Mac.

## Install

1. Download `Polish-<version>.dmg` from the [latest release](https://github.com/jasmedia/Polish/releases/latest), open it and drag **Polish** to **Applications**.
2. Open Polish. Releases are not notarized by Apple (that needs a paid developer account), so macOS blocks the first launch with a warning. Go to **System Settings › Privacy & Security**, scroll to the message about Polish and click **Open Anyway**, then confirm. You only do this once per download.

   If you prefer Terminal, this clears the download flag instead:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Polish.app
   ```

3. Follow the welcome guide. It asks for **Accessibility** access, which Polish needs to read the message you're typing and put the corrected text back.

Requires macOS 27 on Apple Silicon with Apple Intelligence turned on (System Settings › Apple Intelligence & Siri).

**Updating:** quit Polish, replace the app in Applications, then turn Polish off and on again in **System Settings › Privacy & Security › Accessibility**. macOS ties that permission to the exact build, so each new version has to be allowed again.

**Checking the download:** each release has a `.sha256` file. In the folder with both files, run `shasum -a 256 -c Polish-*.dmg.sha256`.

You can also build Polish yourself (see [Build from source](#build-from-source)). An app you build on your own Mac opens without the warning.

## Use

- **⌃⌥G** in Slack (or any text field): Polish reads your draft and shows the rewrite in a panel under the caret, changes highlighted. **Return** puts it back, **⌘E** edits it first, **⌘C** copies it, **Tab** tries the next tone, **Esc** leaves your text as it was.
- **⌃⌥⇧G** or **Quick Polish…** in the menu bar: a window to type or paste text, polish it and copy the result.
- **Services › Polish Text** in any app's menu, with text selected.
- **Settings:** default tone (Keep my tone, Casual, Professional, Concise), shortcuts, a list of changes with a reason for each fix, and a personal dictionary of names and words Polish never changes.

## Build from source

Requirements:

- macOS 27 on Apple Silicon, with Apple Intelligence turned on
- Xcode 27 installed (for the Swift toolchain and macOS SDK; the IDE is optional)
- [uv](https://docs.astral.sh/uv/) for the Python evaluation tools

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
| `scripts/` | `bundle.sh` (build + sign the .app), `run.sh`, `bootstrap.sh`, `release.sh` (release DMG), `make-icon.swift` |

## Releases

Push a tag that matches the version in `App/Info.plist`, and the Release workflow tests, builds an ad-hoc signed DMG with `scripts/release.sh` and publishes it:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

`make release` builds the same DMG locally in `.build/release-dist/`. With a paid Apple Developer account, `NOTARIZE=1 make release` signs with Developer ID and notarizes instead (setup steps at the top of `scripts/release.sh`).

## Tests

```bash
make test-core   # PolishCore engine tests
make test-app    # app tests
make test        # both
```

CI runs both on GitHub's `xcode-27` runners. The on-device model is not available on CI, so tests that need it skip themselves there and run only on a Mac with Apple Intelligence.

## Privacy

Polish uses only the on-device `SystemLanguageModel`. It makes no network calls, keeps no copy of your messages, and logs message text only as private. The app has no network entitlement.

## License

MIT
