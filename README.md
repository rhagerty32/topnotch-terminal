# TopNotch Terminal

**A login shell that lives in the MacBook notch—hover the camera housing to open it, move away to hide it.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/rhagerty32/topnotch-terminal/actions/workflows/ci.yml/badge.svg)](https://github.com/rhagerty32/topnotch-terminal/actions/workflows/ci.yml)

<p align="center">
  <img src="topnotch-terminal-icon.png" alt="TopNotch Terminal app icon" width="256">
  <br>
  <em>Screen recording or demo GIF welcome—replace this block when you have one.</em>
</p>

TopNotch Terminal is a menu-bar accessory for **macOS 14+** on MacBooks with a notch. Nothing is drawn while idle. Hover to open; the terminal takes keyboard focus immediately. Leave the notch and it closes unless you pin it.

Pin when you want it to stay. Pop it out for a normal window. A running command shows a small **busy island** in the notch so you can see the job is still going.

The app is not sandboxed, so the login shell can run real tools. It does not appear in the Dock.

## Features

- **Notch-native UI** — Opens on hover, hides when you leave (configurable timing in Settings).
- **Pin and pop-out** — Stay open in the notch, or detach to a regular window (`kick` / `kickback` CLI helpers).
- **Tabs** — ⌘T new tab; tab rail appears when you have more than one.
- **Text-field editing** — Mac-style selection and clipboard shortcuts instead of raw terminal chords.
- **Shell integration** — Bundled `kick`, `kickback`, and `focus` on `PATH`; your `~/.zshenv` and `~/.zshrc` still load.
- **Settings** — Shell path, font size, hover delays, open at login (menu extra).

## Install

There are no signed release binaries on GitHub yet. To try it today, [build from source](#build-from-source) or use a DMG you built locally (see below).

### Share a DMG (local build)

`make dmg` produces `dist/TopNotchTerminal-0.1.0.dmg`. Friends drag **TopNotch Terminal** into Applications.

This build is **ad-hoc signed**. macOS warns that it is from an unidentified developer. First launch: right-click → **Open**, or:

```bash
xattr -dr com.apple.quarantine "/Applications/TopNotch Terminal.app"
```

A warning-free install needs an Apple Developer Program membership, a Developer ID Application certificate, and notarization before packaging.

## Using the terminal

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

Editing follows the Mac text field, not raw terminal chords. Shift-arrows grow a selection. ⌘A selects the command line. ⌘C, ⌘X, and ⌘V copy, cut, and paste. Left and right arrow move to that side of the highlight and leave the text in place. ⌘←/⌘→ and ⌥←/⌥→ jump and delete by line or word the way a text field does.

## Build from source

You need **Xcode** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`).

```bash
make open
```

That generates the project, builds Debug, quits the copy already sitting in the notch, and launches the new one. A plain `open` only wakes the old process.

Current Xcode ships `metal` as a stub and downloads the real compiler separately. `make` runs `scripts/metal-developer-dir.sh`, which downloads nothing by itself. If the compiler is missing:

```bash
xcodebuild -downloadComponent MetalToolchain
make open
```

| Target | Description |
| --- | --- |
| `make build` | Debug build only |
| `make release` | Release build |
| `make dmg` | Release build + `dist/TopNotchTerminal-0.1.0.dmg` |

Open `TopNotchTerminal.xcodeproj` after `xcodegen generate` if you want to run from Xcode.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for build steps, branch flow, and code conventions. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE) © Ryan Hagerty
