# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Build

Requirements: macOS 26, Xcode 26, an Android SDK (Android Studio or `brew install --cask android-platform-tools`).

```sh
brew install xcodegen
xcodegen generate        # the .xcodeproj is generated, never committed
open OhMyAndroid.xcodeproj
```

Local builds are ad-hoc signed, so no Apple Developer account is needed.

## Rules of the code

- Swift 6 language mode, strict concurrency, **zero warnings** (warnings are errors).
- Dependency direction: `UI → State → Features → Core`. Features import Foundation only;
  anything with AppKit (pickers, clipboard, Finder) goes through `HostActions`.
- Nothing polls. Device changes come from the adb server's `track-devices` socket (no child process that could outlive the app); feature values are read on demand.
- Every `Process` goes through `ShellRunning`: non-blocking, with a watchdog timeout.
- Text from the user is quoted with `String.shellQuoted` before it reaches `adb shell`.
- Destructive actions set `isDestructive = true`; the panel then asks before running them.

## Add a feature

1. Create a struct in `Sources/Features/` that conforms to one of `ToggleFeature`,
   `StepperFeature`, `ChoiceFeature`, `ActionFeature`, `TextActionFeature`.
2. If its state is one shell command, also conform to `BatchReadable` so it is read in the shared
   round-trip.
3. Set `requiresEmulator = true` if it uses the emulator console (`adb emu …`).
4. Append it to `FeatureCatalog.all`. The panel renders it, reads its state, and shows errors as toasts.

Check your command on an emulator and, if it is not emulator-only, on a real device.

## Add an MCP tool

The MCP server (`Sources/MCP/`) is a separate command-line target built from `Core` and `Features`.

1. Add a `Tool` to one of the groups in `Sources/MCP/Tools/`. Reuse a feature when one exists.
2. Set `effect`: `.read` (Read only access), `.control` or `.destructive` (Full control). It also sets
   the MCP annotations clients use to ask the user.
3. Keep it cheap for the model: one-line description, positions in dp, compact text output.
   Validate every argument that reaches a shell command.
4. Run the protocol test: `Scripts/test-mcp.py <path>/ohmyandroid-mcp` (CI runs it too), then try the
   tool on an emulator with `npx @modelcontextprotocol/inspector --cli <path>/ohmyandroid-mcp`.

Never write to stdout in the server: stdout carries JSON-RPC only.

## Release (maintainers)

```sh
xcrun notarytool store-credentials ohmyandroid --apple-id <email> --team-id <TEAM_ID>   # once
TEAM_ID=<TEAM_ID> Scripts/release.sh
```

Then attach `dist/OhMyAndroid-<version>.zip`, `dist/appcast.xml` and `dist/oh-my-android-<version>.mcpb`
to a GitHub release tagged `v<version>`, and copy `dist/oh-my-android.rb` to the Homebrew tap.

The script also updates `server.json` (version, `.mcpb` URL and sha256). Commit it, then publish to the
[MCP Registry](https://registry.modelcontextprotocol.io) (`brew install mcp-publisher`):

```sh
mcp-publisher login github   # once
mcp-publisher publish
```

`mcpb/manifest.json` is the Claude Desktop extension manifest; its version is set by the script.
