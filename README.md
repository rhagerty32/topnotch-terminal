# TopNotch Terminal

A login shell that lives in the MacBook notch. Hover the camera housing and it opens. Move the pointer away and it disappears. Nothing is drawn while it is idle.

Pin it when you want it to stay. Pop it out when you want a normal window. A running command leaves a small island in the notch so you can see the job is still going.

The app is a menu-bar accessory. It does not take a Dock icon. It is not sandboxed, so the login shell can run real tools. macOS 14 or later.

## Use it

Hover to open. The terminal takes the keyboard as soon as it is open, so you can type without pinning. Leave and it closes, unless it is pinned.

| Action | How |
| --- | --- |
| Pin or unpin | Toolbar pin, or the menu extra |
| Pop out to a window | Toolbar window button, or type `kick` |
| Send the window back to the notch | Window toolbar, close the window, or type `kickback` |
| Show it from another app | Menu extra **Show Terminal**, or type `focus` |
| New tab | ⌘T. The tab rail stays hidden until a second tab exists |
| Close tab | ⌘W. The last tab stays open |
| Switch tab | ⌘1–⌘9, or Control-Tab |
| Hide | Escape, when nothing is running |
| Settings | Menu extra. Shell, font size, hover timing, open at login |
| Quit | Menu extra. Every session ends |

`kick`, `kickback`, and `focus` are on the shell `PATH` inside the app. Your own `~/.zshenv` and `~/.zshrc` still load.

Editing follows the Mac text field, not raw terminal chords. Shift-arrows grow a selection. ⌘A selects the command line. ⌘C, ⌘X, and ⌘V copy, cut, and paste. Left and right arrow move to that side of the highlight and leave the text in place. ⌘←/⌘→ and ⌥←/⌥→ jump and delete by line or word the way a text field does.

## Build

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make open
```

That generates the project, builds Debug, quits the copy already sitting in the notch, and launches the new one. A plain `open` only wakes the old process.

Current Xcode ships `metal` as a stub and downloads the real compiler separately. `make` runs `scripts/metal-developer-dir.sh`, which downloads nothing by itself. If the compiler is missing:

```bash
xcodebuild -downloadComponent MetalToolchain
make open
```

`make release` builds the Release app. `make dmg` builds Release and writes `dist/TopNotchTerminal-0.1.0.dmg`.

Open `TopNotchTerminal.xcodeproj` after `xcodegen generate` if you want to run it from Xcode.

## Share a DMG

Friends drag **TopNotch Terminal** up into the notch (Applications).

This build is ad-hoc signed. macOS warns that it is from an unidentified developer. The first launch has to be right-click → **Open**, or:

```bash
xattr -dr com.apple.quarantine "/Applications/TopNotch Terminal.app"
```

A warning-free install needs an Apple Developer Program membership and a Developer ID Application certificate, then sign and notarize before making the DMG.
