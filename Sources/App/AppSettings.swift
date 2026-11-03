import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let fontSize = "fontSize"
        static let shellPath = "shellPath"
        static let hoverEnter = "hoverEnterMs"
        static let hoverLeave = "hoverLeaveMs"
    }

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }

    @Published var shellPath: String {
        didSet { UserDefaults.standard.set(shellPath, forKey: Key.shellPath) }
    }

    @Published var hoverEnterMs: Double {
        didSet { UserDefaults.standard.set(hoverEnterMs, forKey: Key.hoverEnter) }
    }

    @Published var hoverLeaveMs: Double {
        didSet { UserDefaults.standard.set(hoverLeaveMs, forKey: Key.hoverLeave) }
    }

    var resolvedShell: String {
        if !shellPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shellPath
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var enterDelay: TimeInterval { hoverEnterMs / 1000 }
    var leaveDelay: TimeInterval { hoverLeaveMs / 1000 }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private init() {
        let storedSize = UserDefaults.standard.double(forKey: Key.fontSize)
        fontSize = storedSize > 0 ? storedSize : 12
        shellPath = UserDefaults.standard.string(forKey: Key.shellPath) ?? ""
        let enter = UserDefaults.standard.double(forKey: Key.hoverEnter)
        hoverEnterMs = enter > 0 ? enter : 120
        let leave = UserDefaults.standard.double(forKey: Key.hoverLeave)
        hoverLeaveMs = leave > 0 ? leave : 400
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
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
        objectWillChange.send()
    }
}
