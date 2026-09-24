# Security

Oyama runs `adb` commands on your Android devices and reads private app data of debuggable apps.
Please report security problems privately.

## Report a vulnerability

Use GitHub's **Report a vulnerability** button on the Security tab of this repository.
Do not open a public issue.

## What Oyama does and does not do

- No network access of its own. No analytics, no telemetry, no update checks.
- Talks only to the local `adb` from your Android SDK. Nothing is bundled.
- The Data Inspector reads app storage through `run-as`, which Android allows only for
  `debuggable=true` builds. It never writes to the device. Pulled database copies live in the
  macOS temporary folder and are deleted when you reload and when Oyama quits.
- Text you type (deep links, text input, SMS) is shell-quoted before it reaches the device shell.
- Not sandboxed: the App Sandbox cannot start `adb`. Release builds are signed with a Developer ID,
  use the hardened runtime, and are notarized by Apple.
