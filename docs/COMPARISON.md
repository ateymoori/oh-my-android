# Oh My Android compared

An honest look at the tools Android developers already use, and where Oh My Android fits.
Checked on 2026-09-26 from each project's docs and GitHub. Corrections are welcome: open an issue.

## At a glance

| | Oh My Android | Android Studio | scrcpy | mobile-mcp | androidtool-mac |
|---|---|---|---|---|---|
| Runs on | macOS 26+ | Windows, macOS, Linux | Windows, macOS, Linux | Node (macOS, Linux, Windows) | macOS |
| Price / license | Free, MIT | Free | Free, Apache-2.0 | Free, Apache-2.0 (paid cloud devices optional) | Free, Apache-2.0 |
| Maintained | Yes | Yes | Yes | Yes | No (last commit 2018) |
| Emulators / phones | Both | Both | Both | Both, plus iOS | Phones (emulators not documented) |
| Dark mode, font size, app language, TalkBack in one click | Yes, emulators and phones | Yes: Device UI shortcuts (API 33+; TalkBack needs Accessibility Suite) | No | No | No |
| Bold text, pseudo-locales, layout bounds, show taps, animations | One click each | Not in the shortcuts | No | No | No |
| Network speed, GPS, battery (emulator) | Yes | Yes: Extended Controls, more options (GPS routes, sensors, camera) | No | GPS only | No |
| Screenshots / screen recording | Yes; MCP screenshots are 1 px = 1 dp | Yes | Recording and mirroring | Yes | Yes, plus GIF |
| Layout inspection | Any app, in dp, with design overlay | Layout Inspector, debuggable apps | No | Element list for agents | No |
| App data | SharedPreferences and SQLite, debuggable apps | Database Inspector with live queries; prefs as raw files | No | No | No |
| Screen mirroring with input | No | Yes | Yes, with audio, camera, HID | No | No |
| MCP server for AI agents | Yes, 18 tools, dp coordinates | Not found in the docs | No | Yes, about 32 tools | No |

## When to use what

- **Android Studio** is already open for most Android work, and its Device UI shortcuts cover dark mode,
  font size, screen size, app language and TalkBack on API 33+. Extended Controls go deeper for emulator sensors, camera
  and GPS routes. Oh My Android puts the everyday toggles for emulators *and* phones in one always-visible
  panel, adds the ones Studio does not have (bold text, pseudo-locales, layout bounds, show taps), and works
  when Studio is closed.
- **scrcpy** is the tool for mirroring a phone to your Mac and controlling it with keyboard and mouse.
  Oh My Android does not mirror; the two work well side by side.
- **mobile-mcp** is the choice when your agent must also drive iOS or cloud devices. Oh My Android's MCP
  server is Android only; it adds device settings (dark mode, RTL, font scale, TalkBack, network), app data,
  accessibility audits, and screenshots and UI trees in dp, the units of your layout code.
- **androidtool-mac** was the classic Mac helper for screenshots and APK installs. It has not been updated
  since 2018.
