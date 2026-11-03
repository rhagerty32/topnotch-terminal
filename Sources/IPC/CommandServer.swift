import Darwin
import Foundation

@MainActor
final class CommandServer {
    var handler: ((IPCCommand) -> Void)?

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    func start() {
        let path = IPC.socketPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

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

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindOK == 0, listen(listenFD, 4) == 0 else {
            close(listenFD)
            listenFD = -1
            return
        }

        let fd = listenFD
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        src.setCancelHandler {
            close(fd)
            unlink(path)
        }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        listenFD = -1
    }

    private func acceptOnce() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 64)
        let n = read(client, &buffer, buffer.count)
        close(client)
        guard n > 0 else { return }
        let raw = String(decoding: buffer[0..<n], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let command = IPCCommand(rawValue: raw) else { return }
        handler?(command)
    }
}
