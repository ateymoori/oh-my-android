# Security

Oh My Android runs `adb` commands on your Android devices and reads private app data of debuggable apps.
Please report security problems privately.

## Report a vulnerability

Use GitHub's **Report a vulnerability** button on the Security tab of this repository.
Do not open a public issue.

## What Oh My Android does and does not do

- No analytics, no telemetry. The only network request of its own is the update check
  ([Sparkle](https://sparkle-project.org)): once a day, a GET of `appcast.xml` from this repository's
  latest GitHub release. It can be turned off in Settings → Updates.
- Updates install only when the user chooses. Sparkle rejects an update unless the zip and the feed
  are signed with this project's EdDSA key (public key in Info.plist) and the app has the same Developer ID.
- Talks only to the local `adb` from your Android SDK. The only bundled code is Sparkle.
- The Data Inspector reads app storage through `run-as`, which Android allows only for
  `debuggable=true` builds. It never writes to the device. Pulled database copies live in the
  macOS temporary folder and are deleted when you reload and when Oh My Android quits.
- Text you type (deep links, text input, SMS) is shell-quoted before it reaches the device shell.
- Not sandboxed: the App Sandbox cannot start `adb`. Release builds are signed with a Developer ID,
  use the hardened runtime, and are notarized by Apple.
