import AppKit
import Foundation

@MainActor
final class SessionStore {
    private(set) var sessions: [TerminalSession] = []
    private(set) var selectedID: UUID?
    var onChange: (() -> Void)?

    private var busyTimer: Timer?

    var selected: TerminalSession? {
        sessions.first { $0.id == selectedID } ?? sessions.first
    }

    var isAnyBusy: Bool {
        sessions.contains(where: \.isBusy)
    }

    init() {
        addTab()
        busyTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollBusy()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .topNotchSessionDidDie,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let id = (note.object as? TerminalSession)?.id
            MainActor.assumeIsolated {
                guard let id else { return }
                self?.replaceDead(id: id)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .topNotchSessionChromeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.emit()
            }
        }
    }

    func addTab() {
        let session = TerminalSession()
        sessions.append(session)
        selectedID = session.id
        session.startIfNeeded()
        emit()
    }

    func closeSelected() {
        guard sessions.count > 1, let selected else { return }
        close(selected)
    }

    func close(_ session: TerminalSession) {
        guard sessions.count > 1 else { return }
        session.terminate()
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id {
            selectedID = sessions.last?.id
        }
        emit()
    }

    func rename(_ id: UUID, to name: String) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.rename(name)
        emit()
    }

    func select(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedID = id
        emit()
    }

    func selectIndex(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        selectedID = sessions[index].id
        emit()
    }

    func cycle(forward: Bool) {
        guard let selectedID, let idx = sessions.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = forward
            ? (idx + 1) % sessions.count
            : (idx - 1 + sessions.count) % sessions.count
        self.selectedID = sessions[next].id
        emit()
    }

    func terminateAll() {
        busyTimer?.invalidate()
        for session in sessions {
            session.terminate()
        }
        sessions.removeAll()
    }

    private func replaceDead(id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        replaceDead(session)
    }

    private func replaceDead(_ session: TerminalSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        if sessions.count == 1 {
            let replacement = TerminalSession()
            sessions[idx] = replacement
            selectedID = replacement.id
            replacement.startIfNeeded()
        } else {
            sessions.remove(at: idx)
            if selectedID == session.id {
                selectedID = sessions[min(idx, sessions.count - 1)].id
            }
        }
        emit()
    }

    private func pollBusy() {
        var changed = false
        for session in sessions {
            let before = session.isBusy
            session.refreshBusy()
            if before != session.isBusy { changed = true }
        }
        if changed { emit() }
    }

    private func emit() {
        onChange?()
        NotificationCenter.default.post(name: .topNotchStoreDidChange, object: self)
    }
}
