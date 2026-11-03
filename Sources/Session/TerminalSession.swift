import AppKit
import Darwin
import SwiftTerm

final class TrackingTerminalView: LocalProcessTerminalView {
    var onSubmitCommand: ((String) -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if data.contains(where: { $0 == 0x0d || $0 == 0x0a }) {
            if let command = CommandLineReader.command(from: getTerminal()) {
                onSubmitCommand?(command)
            }
        }
        super.send(source: source, data: data)
    }
}

enum CommandLineReader {
    static let promptMarkers = ["% ", "$ ", "# ", "> ", "❯ ", "➜ "]
    private static let pathPromptNeedles = ["/ %", "/ $", "/ #", "/ ❯", "/ ➜"]

    static func command(from terminal: Terminal) -> String? {
        let line = String(lineCharacters(row: terminal.buffer.y, terminal: terminal))
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return stripPrompt(line)
    }

    /// One visible character per screen column on `row`.
    static func lineCharacters(row: Int, terminal: Terminal) -> [Character] {
        (0..<terminal.cols).map { col in
            let ch = terminal.getCharacter(col: col, row: row) ?? " "
            return ch == "\0" ? " " : ch
        }
    }

    /// Screen column of the first typed cell — after ` / %` or the last prompt marker.
    static func promptEndColumn(row: Int, terminal: Terminal) -> Int? {
        let cells = lineCharacters(row: row, terminal: terminal)
        let line = String(cells)

        for needle in pathPromptNeedles {
            if let range = line.range(of: needle) {
                return skipSpaces(line.distance(from: line.startIndex, to: range.upperBound), in: cells)
            }
        }

        var best: Int?
        for marker in promptMarkers {
            guard let range = line.range(of: marker, options: .backwards) else { continue }
            let col = line.distance(from: line.startIndex, to: range.upperBound)
            if best == nil || col > best! { best = col }
        }
        if let best {
            return skipSpaces(best, in: cells)
        }

        return nil
    }

    private static func skipSpaces(_ column: Int, in cells: [Character]) -> Int {
        var col = column
        while col < cells.count, cells[col].isWhitespace { col += 1 }
        return col
    }

    private static func stripPrompt(_ line: String) -> String? {
        var cut: String.Index?
        for marker in promptMarkers {
            if let range = line.range(of: marker, options: .backwards) {
                if cut == nil || range.upperBound > cut! {
                    cut = range.upperBound
                }
            }
        }
        let command = (cut.map { String(line[$0...]) } ?? line)
            .trimmingCharacters(in: .whitespaces)
        return command.isEmpty ? nil : command
    }
}

final class TerminalSession: NSObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let hostView: TrackingTerminalView

    var title: String = "zsh"
    var cwd: String?
    var lastCommand: String?
    var customTitle: String?
    var isBusy = false
    private var started = false

    var tabTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        if let lastCommand, !lastCommand.isEmpty {
            return lastCommand
        }
        return "zsh"
    }

    override init() {
        hostView = TrackingTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        super.init()
        hostView.processDelegate = self
        hostView.nativeBackgroundColor = .black
        hostView.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        hostView.caretColor = NSColor(white: 0.92, alpha: 1)
        hostView.autoresizingMask = [.width, .height]
        hostView.onSubmitCommand = { [weak self] command in
            guard let self else { return }
            self.lastCommand = command
            NotificationCenter.default.post(name: .topNotchSessionChromeDidChange, object: self)
        }
    }

    @MainActor
    func startIfNeeded() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        let shell = settings.resolvedShell
        let launcher = Bundle.main.resourceURL?
            .appendingPathComponent("bin/tnt-shell", isDirectory: false)
            .path
        if let launcher, FileManager.default.isExecutableFile(atPath: launcher) {
            // Accessory apps are the "responsible process" for PTY children, so
            // GUI launches (Cursor, open -a, …) stay in the background. Spawn
            // the shell through tnt-shell so it disclaims that responsibility.
            hostView.startProcess(
                executable: launcher,
                args: [shell, "-l"],
                environment: Self.processEnvironment()
            )
        } else {
            hostView.startProcess(
                executable: shell,
                args: ["-l"],
                environment: Self.processEnvironment(),
                execName: (shell as NSString).lastPathComponent
            )
        }
    }

    func terminate() {
        hostView.terminate()
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = trimmed.isEmpty ? nil : trimmed
        NotificationCenter.default.post(name: .topNotchSessionChromeDidChange, object: self)
    }

    func refreshBusy() {
        let fd = hostView.process.childfd
        let pid = hostView.process.shellPid
        isBusy = Self.isForegroundBusy(fd: fd, shellPid: pid)
    }

    var label: String { tabTitle }

    private static func isForegroundBusy(fd: Int32, shellPid: pid_t) -> Bool {
        guard fd >= 0, shellPid > 0 else { return false }
        var pgid = tcgetpgrp(fd)
        if pgid <= 0 {
            var group: pid_t = 0
            let result = ioctl(fd, TIOCGPGRP, &group)
            guard result == 0, group > 0 else { return false }
            pgid = group
        }
        return !isIdleShellPgid(pgid, wrapperPid: shellPid)
    }

    /// tnt-shell stays as the PTY child; zsh is its (disclaimed) child and owns
    /// the foreground group while idle.
    private static func isIdleShellPgid(_ pgid: pid_t, wrapperPid: pid_t) -> Bool {
        if pgid == wrapperPid || getpgid(wrapperPid) == pgid {
            return true
        }
        for child in childPids(of: wrapperPid) {
            if pgid == child || getpgid(child) == pgid {
                return true
            }
        }
        return false
    }

    private static func childPids(of parent: pid_t) -> [pid_t] {
        let neededBytes = proc_listchildpids(parent, nil, 0)
        guard neededBytes > 0 else { return [] }
        let stride = MemoryLayout<pid_t>.stride
        let capacity = max(1, Int(neededBytes) / stride)
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listchildpids(parent, buf.baseAddress, Int32(buf.count * stride))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    static func processEnvironment() -> [String] {
        var dict = ProcessInfo.processInfo.environment
        for key in dict.keys where key.hasPrefix("DYLD_") || key.hasPrefix("__XPC") || key.hasPrefix("XPC_") {
            dict.removeValue(forKey: key)
        }
        let inheritedPath = dict["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        let bin = Bundle.main.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .path
        if let bin {
            dict["PATH"] = "\(bin):\(inheritedPath)"
        }
        dict["TERM"] = "xterm-256color"
        dict["COLORTERM"] = "truecolor"
        dict["TERM_PROGRAM"] = "TopNotchTerminal"
        dict["TOPNOTCH_SOCKET"] = IPC.socketPath
        if let zdot = Self.installZshDotDir() {
            dict["ZDOTDIR"] = zdot
        }
        return dict.map { "\($0.key)=\($0.value)" }
    }

    /// Writable ZDOTDIR with our rc files (the bundle is a bad place for .zcompdump).
    private static func installZshDotDir() -> String? {
        let fm = FileManager.default
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("zsh", isDirectory: true),
              let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let zdot = support
            .appendingPathComponent("TopNotch Terminal", isDirectory: true)
            .appendingPathComponent("zsh", isDirectory: true)
        do {
            try fm.createDirectory(at: zdot, withIntermediateDirectories: true)
            for name in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
                let src = bundled.appendingPathComponent(name)
                let dst = zdot.appendingPathComponent(name)
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                if fm.fileExists(atPath: src.path) {
                    try fm.copyItem(at: src, to: dst)
                }
            }
            return zdot.path
        } catch {
            return bundled.path
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title.isEmpty ? self.title : title
        NotificationCenter.default.post(name: .topNotchSessionChromeDidChange, object: self)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        cwd = directory
        NotificationCenter.default.post(name: .topNotchSessionChromeDidChange, object: self)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NotificationCenter.default.post(name: .topNotchSessionDidDie, object: self)
    }
}

extension Notification.Name {
    static let topNotchSessionChromeDidChange = Notification.Name("topNotchSessionChromeDidChange")
    static let topNotchSessionDidDie = Notification.Name("topNotchSessionDidDie")
    static let topNotchStoreDidChange = Notification.Name("topNotchStoreDidChange")
}
