# Security

## Reporting a vulnerability

Please report security issues privately through GitHub: **Security › Report a vulnerability** on
this repository. Don't open a public issue. You should hear back within a week.

Only the latest release is supported; fixes ship as a new release.

## What Polish can access

Polish reads and replaces text in other apps, so it needs more access than most menu bar apps:

- **Accessibility permission.** Used to read the focused text field and to send ⌘A, ⌘C and ⌘V to
  the frontmost app. With it, an app can see and type into other apps' windows. Polish only acts
  when you press its hotkey, use Quick Polish, or choose Services › Polish Text.
- **No App Sandbox.** Cross-app Accessibility and synthetic keystrokes don't work inside the
  sandbox, which is also why Polish isn't on the App Store.
- **Clipboard.** Polish copies the draft to read it and pastes the corrected text back.

## What it doesn't do

- **No network.** The app has no network entitlement and makes no network calls. Text is rewritten
  by Apple's on-device Foundation Model (`SystemLanguageModel`), never Private Cloud Compute or a
  remote service.
- **No analytics or telemetry.**
- **No message text in logs.** Logs (subsystem `com.jasmedia.polish`) mark any user text as
  private, so it is redacted in Console and `log stream`; only timings, token counts and error
  codes are public.
- **Never edits your text without review.** Every change is shown in the review panel first, and
  on any error your original text stays as it was.

## Releases

Releases are built by [`.github/workflows/release.yml`](.github/workflows/release.yml) on GitHub
Actions from a tagged commit and published as a DMG on the Releases page. They are **ad-hoc signed
and not notarized**, so macOS can't vouch for them: download Polish only from this repository's
Releases page, or build it yourself from source (`make run`, see the README).
