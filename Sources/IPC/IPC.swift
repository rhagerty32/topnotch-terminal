import Darwin
import Foundation

enum IPCCommand: String, Sendable {
    case kick
    case kickback
    case focus
}

enum IPC {
    static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["TOPNOTCH_SOCKET"], !override.isEmpty {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/TopNotchTerminal", isDirectory: true)
            .appendingPathComponent("ipc.sock")
            .path
    }

    static func send(_ command: IPCCommand, to path: String = socketPath) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("topnotch: could not create socket\n", stderr)
            exit(1)
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    strncpy(dst, cstr, maxLen - 1)
                }
            }
        }

        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            fputs("topnotch: not running (no socket at \(path))\n", stderr)
            exit(1)
        }

        var payload = command.rawValue + "\n"
        payload.withUTF8 { buf in
            guard let base = buf.baseAddress else { return }
            _ = write(fd, base, buf.count)
        }
    }
}
