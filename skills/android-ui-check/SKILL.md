---
name: android-ui-check
description: Check and drive an Android app's UI on an emulator or phone with the oh-my-android MCP tools. Use when building or fixing Android screens, verifying a UI change, or testing dark mode, large fonts, RTL or pseudo-locales.
---

# Android UI check

Use the `oh-my-android` MCP tools. Positions are in **dp**, the same unit as layout code.

## get_ui or screenshot

- `get_ui` first: a compact tree with refs, text and bounds in dp. Use it to find elements, read text and plan taps. It costs far fewer tokens than an image.
- `screenshot` when you must see the result: colors, images, clipping, overlap, alignment. It is scaled so 1 px = 1 dp.

## The loop

1. `get_ui` to see the current screen.
2. Act: `tap` (by ref from the last `get_ui`, visible text, or x,y in dp), `type_text`, `swipe`, `press_key`.
3. `get_ui` again to confirm the change. Refs can change after every action, so never reuse old refs.

On a crash, read `logcat`.

## UI matrix check

1. Call `get_device_state` and note the current dark mode, font scale and locale.
2. Check the screen with `set_device_settings` in each setup, one at a time, with `get_ui` or `screenshot` after each:
   - `dark_mode: true`
   - `font_scale: 2`
   - `locale: "ar"` (RTL)
   - `locale: "en-XA"` (pseudo-locale with long text)
3. Look for cut-off or overlapping text, wrong mirroring, low contrast, and hard-coded strings.
4. **Restore** the settings you noted in step 1.

`accessibility_audit` finds missing labels and touch targets smaller than 48 × 48 dp.
