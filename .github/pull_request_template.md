## What and why

## Checklist
- [ ] `xcodegen generate && xcodebuild -scheme OhMyAndroid build` passes with zero warnings
- [ ] Tested on an emulator and, if the feature is not emulator-only, on a device
- [ ] New features are one type in `Sources/Features/`, registered in `FeatureCatalog`
- [ ] User text is quoted with `shellQuoted` before it reaches `adb shell`
