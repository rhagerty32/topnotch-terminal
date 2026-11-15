import AppKit
import SwiftUI

/// The SwiftUI `Settings` scene does not open a window while the app is a
/// menu-bar accessory. This window is the one Finder, the gear, and ⌘, use.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let host = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 520))
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        // Stay an accessory so opening Settings does not plant a Dock icon.
        // orderFrontRegardless is what actually raises the window for a menu-bar app.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case notch
    case shell
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .notch: "Notch"
        case .shell: "Shell"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "textformat"
        case .notch: "macwindow"
        case .shell: "terminal"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if settings.showFirstLaunchHint {
                        Text("Hover the camera housing to type. This window is where you tune the terminal.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch pane {
                    case .general:
                        GeneralPane(settings: settings)
                    case .appearance:
                        AppearancePane(settings: settings)
                    case .notch:
                        NotchPane(settings: settings)
                    case .shell:
                        ShellPane(settings: settings)
                    case .shortcuts:
                        ShortcutsPane(settings: settings)
                    }
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 480, idealHeight: 520)
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "General",
                detail: "Opening the app from Finder or Spotlight uses this. Launch at login stays invisible until you hover."
            )
            Picker("Open the app", selection: $settings.openAppBehavior) {
                ForEach(OpenAppBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            Toggle("Open at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            Toggle("Confirm quit while a job is running", isOn: $settings.confirmQuitWhileBusy)
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Appearance",
                detail: "The card opens black with the notch, then eases into the theme. Type, toolbar, and shell all take that color."
            )
            Picker("Theme", selection: $settings.theme) {
                ForEach(TerminalTheme.allCases) { theme in
                    Text("\(theme.title) · \(theme.detail)").tag(theme)
                }
            }
            Picker("Font", selection: $settings.fontChoice) {
                ForEach(TerminalFontChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            if settings.fontChoice == .custom {
                TextField("PostScript name", text: $settings.customFontName)
                    .textFieldStyle(.roundedBorder)
                if settings.customFontIsMissing {
                    Text("That font isn’t installed. SF Mono is used instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $settings.fontSize, in: 9...18, step: 1) {
                Text("Size: \(Int(settings.fontSize)) pt")
            }
            Picker("Cursor", selection: $settings.cursorKind) {
                ForEach(TerminalCursorKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Toggle("Blink cursor", isOn: $settings.cursorBlink)
            TerminalPreview(settings: settings)
        }
    }
}

private struct TerminalPreview: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let palette = settings.palette
        HStack(spacing: 0) {
            Text("~/src % ")
                .foregroundStyle(Color(nsColor: palette.foreground).opacity(0.55))
            Text("npm run build")
                .foregroundStyle(Color(nsColor: palette.foreground))
            Text(cursorMark)
                .foregroundStyle(Color(nsColor: palette.caret).opacity(settings.cursorBlink ? 0.95 : 0.35))
        }
        .font(Font(settings.resolvedFont()))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: palette.background))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var cursorMark: String {
        switch settings.cursorKind {
        case .block: "█"
        case .bar: "▏"
        case .underline: "▁"
        }
    }
}

private struct NotchPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Notch",
                detail: "Width stays automatic: at least 780pt, half the screen, never past 980. Height is yours."
            )
            HStack(spacing: 8) {
                ForEach(AppSettings.heightPresets, id: \.self) { preset in
                    Button("\(Int(preset))") {
                        settings.selectHeightPreset(preset)
                    }
                    .buttonStyle(.bordered)
                    .tint(abs(settings.cardHeight - preset) < 1 ? Color.accentColor : Color.secondary)
                }
            }
            Text(heightCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Remember the bottom-edge drag", isOn: $settings.rememberDrag)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hover open: \(Int(settings.hoverEnterMs)) ms")
                Slider(value: $settings.hoverEnterMs, in: 0...400, step: 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hover close: \(Int(settings.hoverLeaveMs)) ms")
                Slider(value: $settings.hoverLeaveMs, in: 50...800, step: 10)
            }
            Toggle("Show the command on the busy island", isOn: $settings.showCommandOnIsland)
        }
    }

    private var heightCaption: String {
        if AppSettings.heightPresets.contains(where: { abs($0 - settings.cardHeight) < 1 }) {
            return "Card height \(Int(settings.cardHeight)) pt. Drag the bottom edge of the open notch to resize."
        }
        return "Dragged to \(Int(settings.cardHeight)) pt. Pick a preset to snap back."
    }
}

private struct ShellPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Shell",
                detail: "New tabs start a login shell, so ~/.zshenv and ~/.zshrc still load. These apply to the next tab."
            )
            TextField("Shell", text: $settings.shellPath, prompt: Text(settings.resolvedShell))
                .textFieldStyle(.roundedBorder)
            Text("Leave the shell blank to use $SHELL.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Startup directory", text: $settings.startupDirectory, prompt: Text("~"))
                .textFieldStyle(.roundedBorder)
            Text("Leave the directory blank to start at home.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(
                title: "Shortcuts",
                detail: "Summon works from any app. The chords below stay fixed."
            )
            Picker("Summon", selection: $settings.summonHotkey) {
                ForEach(SummonHotkeyChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ShortcutRow(chord: "⌘T", action: "New tab")
                ShortcutRow(chord: "⌘W", action: "Close tab. The last tab stays.")
                ShortcutRow(chord: "⌘1–⌘9", action: "Switch tab")
                ShortcutRow(chord: "⌃Tab", action: "Next tab")
                ShortcutRow(chord: "Escape", action: "Hide, when nothing is running")
                ShortcutRow(chord: "⌘,", action: "Settings")
            }
            .font(.callout)
        }
    }
}

private struct ShortcutRow: View {
    let chord: String
    let action: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(chord)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 88, alignment: .leading)
            Text(action)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PaneHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}
