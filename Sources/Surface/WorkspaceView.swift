import AppKit

@MainActor
final class WorkspaceView: NSView {
    let store: SessionStore

    private let park = NSView(frame: .zero)
    private let stage = NSView(frame: .zero)
    private let rail = TabRailView()
    private var lastIDs: [UUID] = []
    private var lastSelected: UUID?

    init(store: SessionStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        park.isHidden = true
        stage.wantsLayer = true
        stage.clipsToBounds = true
        stage.layer?.cornerRadius = 0
        stage.layer?.masksToBounds = true
        stage.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(park)
        addSubview(stage)
        addSubview(rail)
        rail.onSelect = { [weak self] id in self?.store.select(id) }
        rail.onNew = { [weak self] in self?.store.addTab() }
        rail.onClose = { [weak self] id in
            guard let session = self?.store.sessions.first(where: { $0.id == id }) else { return }
            self?.store.close(session)
        }
        rail.onRename = { [weak self] id, name in self?.store.rename(id, to: name) }
        reload(focus: false)
    }

    required init?(coder: NSCoder) { nil }

    func reload(focus: Bool = false) {
        let sessions = store.sessions
        let ids = sessions.map(\.id)
        let selectionChanged = store.selectedID != lastSelected
        lastIDs = ids
        lastSelected = store.selectedID

        for session in sessions where session.hostView.superview == nil {
            session.hostView.frame = park.bounds
            park.addSubview(session.hostView)
        }

        for session in sessions {
            let live = session.id == store.selectedID
            session.hostView.isHidden = !live
            if live {
                if session.hostView.superview !== stage {
                    session.hostView.removeFromSuperview()
                    stage.addSubview(session.hostView)
                }
            } else if session.hostView.superview !== park {
                session.hostView.removeFromSuperview()
                park.addSubview(session.hostView)
            }
        }

        let many = sessions.count > 1
        rail.isHidden = !many
        if many {
            rail.reload(sessions: sessions, selected: store.selectedID)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        store.selected?.hostView.frame = stage.bounds
        if focus || selectionChanged, window?.isKeyWindow == true {
            window?.makeFirstResponder(store.selected?.hostView)
        }
    }

    override func layout() {
        super.layout()
        park.frame = NSRect(x: -4000, y: 0, width: 800, height: 600)
        let many = store.sessions.count > 1
        let railWidth = many ? ChromeMetrics.tabRailWidth : 0
        rail.frame = NSRect(x: 0, y: 0, width: railWidth, height: bounds.height)
        stage.frame = NSRect(
            x: railWidth,
            y: 0,
            width: max(0, bounds.width - railWidth),
            height: bounds.height
        )
        let live = stage.bounds
        if store.selected?.hostView.frame != live {
            store.selected?.hostView.frame = live
        }
        for session in store.sessions where session.id != store.selectedID {
            if session.hostView.frame != park.bounds {
                session.hostView.frame = park.bounds
            }
        }
    }
}
