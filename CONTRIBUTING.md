# Contributing to TopNotch Terminal

Thanks for your interest in helping out. This project is a native macOS app; most changes touch Swift, AppKit, and SwiftUI.

## What you need

- **macOS 14 or later** (matches the app deployment target)
- **Xcode** with the macOS SDK
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — `brew install xcodegen`

The app is **not sandboxed** and runs a real login shell. You will want to build and run on a Mac with a notch (or accept that some layout behavior is notch-specific).

## Build and run locally

From the repository root:

```bash
make open
```

That regenerates the Xcode project with XcodeGen, builds the Debug app, quits any running copy, and launches the new build. Using `open` on the `.app` alone can wake an older process that is still resident in the menu bar.

Other useful targets:

| Command | What it does |
| --- | --- |
| `make generate` | Run `xcodegen generate` only |
| `make build` | Generate + Debug `xcodebuild` |
| `make release` | Generate + Release build |
| `make dmg` | Release build and package `dist/TopNotchTerminal-0.1.0.dmg` |

If `xcodebuild` complains about the Metal toolchain, follow the steps in [README.md](README.md#build-from-source).

To work in Xcode: run `make generate` (or any `make` target that depends on it), then open `TopNotchTerminal.xcodeproj`.

Project structure is defined in `project.yml`. After editing that file, regenerate the project before committing.

## Tests

There is no automated test target today. Please manually exercise hover open/close, pin, pop-out (`kick` / `kickback`), tabs, and settings when you change behavior. If you add tests in a follow-up, wire them into CI.

## Branch and pull request flow

1. Fork the repo (or branch from `main` if you have write access).
2. Create a focused branch, e.g. `yourname/short-description`.
3. Keep changes scoped; avoid unrelated formatting sweeps.
4. Open a pull request against `main` and fill out the PR template.
5. Ensure **CI** passes (Debug build on macOS).

Maintainers may suggest edits or merge when the change looks good and the build is green.

## Code style

- **Swift 6** with strict concurrency patterns used elsewhere in the tree (`@MainActor` on UI types, etc.).
- Match existing naming and file layout: feature areas live under `Sources/` (`App`, `Notch`, `Session`, `Surface`, `Window`, `IPC`, `Settings`, `Helpers`).
- Prefer small, readable diffs over large refactors unless discussed first.
- Shell helpers (`kick`, `kickback`, `focus`, `tnt-shell`) are separate targets; shared IPC types live in `Sources/IPC/`.
- Do not commit build artifacts (`build/`, `dist/`, `xcuserdata/`, etc.) — see `.gitignore`.

## Reporting problems and ideas

Use [GitHub Issues](https://github.com/rhagerty32/topnotch-terminal/issues/new/choose) for bugs and feature requests. For conduct concerns, see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
