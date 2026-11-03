# TopNotch Terminal

A persistent SwiftTerm workspace that lives in the MacBook notch: hover to expand, pin to type, `kick` / `kickback` to bounce a real window. Idle collapsed draws nothing. Tabs are Arc-style on the left, hidden until you have more than one.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -scheme TopNotchTerminal -configuration Debug -derivedDataPath build
open "build/Build/Products/Debug/TopNotch Terminal.app"
```

Or open `TopNotchTerminal.xcodeproj` after `xcodegen generate`.

The app is **not sandboxed** so the login shell can run real tools.

## Share a DMG

```bash
make dmg
```

That writes `dist/TopNotchTerminal-0.1.0.dmg`. Friends drag **TopNotch Terminal** up into the notch (Applications).

This build is ad-hoc signed. macOS will warn that it is from an unidentified developer. They should right-click the app → **Open** the first time (or run `xattr -dr com.apple.quarantine "/Applications/TopNotch Terminal.app"`).

For a warning-free install you need an Apple Developer Program membership, a **Developer ID Application** certificate, then sign and notarize the app before making the DMG. Development certificates on this Mac are not enough for friends.

## Use

- Hover the camera housing to expand. Leave to hide.
- Pin (toolbar or status item) to type in the overlay.
- **⌘T** new tab, **⌘W** close tab (keeps the last one).
- Type `kick` in the shell to pop into a window; `kickback` returns pinned to the notch.
- Quit from the menu extra ends every session.
