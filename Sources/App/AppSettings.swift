import AppKit
import Foundation
import ServiceManagement

extension Notification.Name {
    static let topNotchSettingsDidChange = Notification.Name("topNotchSettingsDidChange")
}

enum OpenAppBehavior: String, CaseIterable, Identifiable {
    case settings
    case terminal
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: "Show Settings"
        case .terminal: "Show the terminal"
        case .both: "Settings and the terminal"
        }
    }
}

enum TerminalTheme: String, CaseIterable, Identifiable {
    case ink
    case slate
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: "Ink"
        case .slate: "Slate"
        case .paper: "Paper"
        }
    }

    var detail: String {
        switch self {
        case .ink: "White on black"
        case .slate: "Cooler type"
        case .paper: "Light card"
        }
    }
}

enum TerminalFontChoice: String, CaseIterable, Identifiable {
    case sfMono
    case menlo
    case monaco
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfMono: "SF Mono"
        case .menlo: "Menlo"
        case .monaco: "Monaco"
        case .custom: "Installed font…"
        }
    }
}

enum TerminalCursorKind: String, CaseIterable, Identifiable {
    case block
    case bar
    case underline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block: "Block"
        case .bar: "Bar"
        case .underline: "Underline"
        }
    }
}

enum SummonHotkeyChoice: String, CaseIterable, Identifiable {
    case none
    case controlOptionT
    case optionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .controlOptionT: "⌃⌥T"
        case .optionSpace: "⌥Space"
        case .commandShiftSpace: "⌘⇧Space"
        }
    }
}

struct TerminalPalette {
    var background: NSColor
    var foreground: NSColor
    var caret: NSColor
    var caretText: NSColor

    /// Black shell, light type. Opening the notch always starts here.
    static let notch = TerminalPalette(
        background: .black,
        foreground: NSColor(white: 0.92, alpha: 1),
        caret: NSColor(white: 0.92, alpha: 1),
        caretText: .black
    )

    var isLight: Bool { background.srgbLuminance > 0.62 }

    /// `fraction` 0 is the black notch. 1 is this theme, card and shell together.
    /// A light theme keeps light type until the card is bright enough to flip.
    func washed(fraction: CGFloat) -> TerminalPalette {
        let t = min(1, max(0, fraction))
        if !isLight {
            return Self.notch.mix(t, toward: self)
        }
        let blendedBackground = Self.notch.background.mix(t, toward: background)
        let shift = min(1, max(0, (t - 0.48) / 0.34))
        let blendedForeground = Self.notch.foreground.mix(shift, toward: foreground)
        return TerminalPalette(
            background: blendedBackground,
            foreground: blendedForeground,
            caret: blendedForeground,
            caretText: blendedBackground
        )
    }

    func mix(_ t: CGFloat, toward other: TerminalPalette) -> TerminalPalette {
        TerminalPalette(
            background: background.mix(t, toward: other.background),
            foreground: foreground.mix(t, toward: other.foreground),
            caret: caret.mix(t, toward: other.caret),
            caretText: caretText.mix(t, toward: other.caretText)
        )
    }

    func isClose(to other: TerminalPalette) -> Bool {
        background.isClose(to: other.background) && foreground.isClose(to: other.foreground)
    }
}

extension NSColor {
    var srgbLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    func mix(_ amount: CGFloat, toward other: NSColor) -> NSColor {
        let t = min(1, max(0, amount))
        let from = usingColorSpace(.sRGB) ?? self
        let to = other.usingColorSpace(.sRGB) ?? other
        return from.blended(withFraction: t, of: to) ?? to
    }

    func isClose(to other: NSColor, tolerance: CGFloat = 0.012) -> Bool {
        guard let from = usingColorSpace(.sRGB), let to = other.usingColorSpace(.sRGB) else { return false }
        return abs(from.redComponent - to.redComponent) < tolerance
            && abs(from.greenComponent - to.greenComponent) < tolerance
            && abs(from.blueComponent - to.blueComponent) < tolerance
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let minCardHeight = 280.0
    nonisolated static let maxCardHeight = 900.0
    nonisolated static let heightPresets = [420.0, 540.0, 640.0]

    private enum Key {
        static let fontSize = "fontSize"
        static let fontChoice = "fontChoice"
        static let customFontName = "customFontName"
        static let theme = "terminalTheme"
        static let cursorKind = "cursorKind"
        static let cursorBlink = "cursorBlink"
        static let shellPath = "shellPath"
        static let startupDirectory = "startupDirectory"
        static let hoverEnter = "hoverEnterMs"
        static let hoverLeave = "hoverLeaveMs"
        static let cardHeight = "cardHeight"
        static let heightPreset = "heightPreset"
        static let rememberDrag = "rememberCardDrag"
        static let showCommandOnIsland = "showCommandOnIsland"
        static let openAppBehavior = "openAppBehavior"
        static let confirmQuitWhileBusy = "confirmQuitWhileBusy"
        static let summonHotkey = "summonHotkey"
        static let hasOpenedSettings = "hasOpenedSettings"
    }

    @Published var fontSize: Double {
        didSet { store(fontSize, key: Key.fontSize, old: oldValue) }
    }

    @Published var fontChoice: TerminalFontChoice {
        didSet { store(fontChoice.rawValue, key: Key.fontChoice, old: oldValue.rawValue) }
    }

    @Published var customFontName: String {
        didSet { store(customFontName, key: Key.customFontName, old: oldValue) }
    }

    @Published var theme: TerminalTheme {
        didSet { store(theme.rawValue, key: Key.theme, old: oldValue.rawValue) }
    }

    @Published var cursorKind: TerminalCursorKind {
        didSet { store(cursorKind.rawValue, key: Key.cursorKind, old: oldValue.rawValue) }
    }

    @Published var cursorBlink: Bool {
        didSet { store(cursorBlink, key: Key.cursorBlink, old: oldValue) }
    }

    @Published var shellPath: String {
        didSet { store(shellPath, key: Key.shellPath, old: oldValue) }
    }

    @Published var startupDirectory: String {
        didSet { store(startupDirectory, key: Key.startupDirectory, old: oldValue) }
    }

    @Published var hoverEnterMs: Double {
        didSet { store(hoverEnterMs, key: Key.hoverEnter, old: oldValue) }
    }

    @Published var hoverLeaveMs: Double {
        didSet { store(hoverLeaveMs, key: Key.hoverLeave, old: oldValue) }
    }

    @Published var cardHeight: Double {
        didSet { storeClampedHeight() }
    }

    @Published var heightPreset: Double {
        didSet { store(heightPreset, key: Key.heightPreset, old: oldValue) }
    }

    @Published var rememberDrag: Bool {
        didSet { store(rememberDrag, key: Key.rememberDrag, old: oldValue) }
    }

    @Published var showCommandOnIsland: Bool {
        didSet { store(showCommandOnIsland, key: Key.showCommandOnIsland, old: oldValue) }
    }

    @Published var openAppBehavior: OpenAppBehavior {
        didSet { store(openAppBehavior.rawValue, key: Key.openAppBehavior, old: oldValue.rawValue) }
    }

    @Published var confirmQuitWhileBusy: Bool {
        didSet { store(confirmQuitWhileBusy, key: Key.confirmQuitWhileBusy, old: oldValue) }
    }

    @Published var summonHotkey: SummonHotkeyChoice {
        didSet { store(summonHotkey.rawValue, key: Key.summonHotkey, old: oldValue.rawValue) }
    }

    @Published var hasOpenedSettings: Bool {
        didSet { store(hasOpenedSettings, key: Key.hasOpenedSettings, old: oldValue) }
    }

    /// Shown in Settings the first time the window opens. Not persisted.
    @Published var showFirstLaunchHint = false

    @Published private(set) var launchAtLogin: Bool

    var resolvedShell: String {
        let trimmed = shellPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Blank means the home directory. An unusable path also falls back to home.
    var resolvedStartupDirectory: String {
        let trimmed = startupDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !trimmed.isEmpty else { return home }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return home
        }
        return expanded
    }

    var customFontIsMissing: Bool {
        guard fontChoice == .custom else { return false }
        let name = customFontName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return NSFont(name: name, size: fontSize) == nil
    }

    var enterDelay: TimeInterval { hoverEnterMs / 1000 }
    var leaveDelay: TimeInterval { hoverLeaveMs / 1000 }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var palette: TerminalPalette {
        switch theme {
        case .ink:
            let fg = NSColor(white: 0.92, alpha: 1)
            return TerminalPalette(background: .black, foreground: fg, caret: fg, caretText: .black)
        case .slate:
            let bg = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1)
            let fg = NSColor(srgbRed: 0.76, green: 0.83, blue: 0.90, alpha: 1)
            return TerminalPalette(background: bg, foreground: fg, caret: fg, caretText: bg)
        case .paper:
            let bg = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1)
            let fg = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
            return TerminalPalette(background: bg, foreground: fg, caret: fg, caretText: bg)
        }
    }

    func resolvedFont() -> NSFont {
        let size = fontSize
        let candidates: [String]
        switch fontChoice {
        case .sfMono:
            candidates = ["SF Mono", "SFMono-Regular", "Menlo"]
        case .menlo:
            candidates = ["Menlo"]
        case .monaco:
            candidates = ["Monaco", "Menlo"]
        case .custom:
            let name = customFontName.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates = name.isEmpty ? ["SF Mono", "Menlo"] : [name, "SF Mono", "Menlo"]
        }
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func selectHeightPreset(_ preset: Double) {
        heightPreset = preset
        cardHeight = preset
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private init() {
        let storedSize = UserDefaults.standard.double(forKey: Key.fontSize)
        fontSize = storedSize > 0 ? min(max(storedSize, 9), 24) : 13
        fontChoice = TerminalFontChoice(rawValue: UserDefaults.standard.string(forKey: Key.fontChoice) ?? "") ?? .sfMono
        customFontName = UserDefaults.standard.string(forKey: Key.customFontName) ?? ""
        theme = TerminalTheme(rawValue: UserDefaults.standard.string(forKey: Key.theme) ?? "") ?? .ink
        cursorKind = TerminalCursorKind(rawValue: UserDefaults.standard.string(forKey: Key.cursorKind) ?? "") ?? .bar
        cursorBlink = Self.storedBool(Key.cursorBlink, default: true)
        shellPath = UserDefaults.standard.string(forKey: Key.shellPath) ?? ""
        startupDirectory = UserDefaults.standard.string(forKey: Key.startupDirectory) ?? ""
        let enter = UserDefaults.standard.double(forKey: Key.hoverEnter)
        hoverEnterMs = enter > 0 ? enter : 120
        let leave = UserDefaults.standard.double(forKey: Key.hoverLeave)
        hoverLeaveMs = leave > 0 ? leave : 400
        let preset = Self.storedDouble(Key.heightPreset, default: Double(ChromeMetrics.expandedHeight))
        let resolvedPreset = Self.heightPresets.contains(preset) ? preset : Double(ChromeMetrics.expandedHeight)
        heightPreset = resolvedPreset
        cardHeight = Self.storedDouble(Key.cardHeight, default: resolvedPreset)
        rememberDrag = Self.storedBool(Key.rememberDrag, default: true)
        showCommandOnIsland = Self.storedBool(Key.showCommandOnIsland, default: true)
        openAppBehavior = OpenAppBehavior(rawValue: UserDefaults.standard.string(forKey: Key.openAppBehavior) ?? "") ?? .settings
        confirmQuitWhileBusy = Self.storedBool(Key.confirmQuitWhileBusy, default: true)
        summonHotkey = SummonHotkeyChoice(rawValue: UserDefaults.standard.string(forKey: Key.summonHotkey) ?? "") ?? .none
        hasOpenedSettings = UserDefaults.standard.bool(forKey: Key.hasOpenedSettings)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func storeClampedHeight() {
        let clamped = min(max(cardHeight, Self.minCardHeight), Self.maxCardHeight)
        if cardHeight != clamped {
            cardHeight = clamped
            return
        }
        guard cardHeight != UserDefaults.standard.double(forKey: Key.cardHeight) || UserDefaults.standard.object(forKey: Key.cardHeight) == nil else {
            return
        }
        UserDefaults.standard.set(cardHeight, forKey: Key.cardHeight)
        publish()
    }

    private func store<T: Equatable>(_ value: T, key: String, old: T) {
        guard value != old else { return }
        UserDefaults.standard.set(value, forKey: key)
        publish()
    }

    private func publish() {
        NotificationCenter.default.post(name: .topNotchSettingsDidChange, object: self)
    }

    private static func storedDouble(_ key: String, default defaultValue: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : defaultValue
    }

    private static func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}

enum SettingsWindow {
    @MainActor
    static func show() {
        SettingsWindowController.shared.show()
    }
}
