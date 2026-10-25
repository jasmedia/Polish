**Install:** open the DMG and drag Polish to Applications. This build isn't notarized by Apple, so the first launch is blocked once: open Polish, then go to System Settings › Privacy & Security and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Polish.app`). Details in the [README](https://github.com/jasmedia/Polish#install).

**Updating:** quit Polish, replace the app in Applications, then turn Polish off and on again in System Settings › Privacy & Security › Accessibility. macOS ties that permission to the exact build.

Requires macOS 27 on Apple Silicon with Apple Intelligence turned on. Check the download against the `.sha256` file with `shasum -a 256 -c Polish-*.dmg.sha256`.
