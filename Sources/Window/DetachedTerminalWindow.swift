import AppKit

@MainActor
final class DetachedTerminalWindow: NSWindow {
    var onMoveToNotch: (() -> Void)?

    private let host = NSView(frame: .zero)

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "TopNotch Terminal"
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        backgroundColor = .black
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        minSize = NSSize(width: 420, height: 240)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        contentView = host
        toolbar = makeToolbar()
        toolbarStyle = .unified
    }

    func embed(_ workspace: WorkspaceView) {
        workspace.removeFromSuperview()
        workspace.frame = host.bounds
        workspace.autoresizingMask = [.width, .height]
        host.addSubview(workspace)
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "TopNotch.Window")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = ToolbarShim.shared
        ToolbarShim.shared.onMove = { [weak self] in self?.onMoveToNotch?() }
        return toolbar
    }
}

@MainActor
private final class ToolbarShim: NSObject, NSToolbarDelegate {
    static let shared = ToolbarShim()
    var onMove: (() -> Void)?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .moveToNotch]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .moveToNotch]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .moveToNotch else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Move to Notch"
        item.paletteLabel = "Move to Notch"
        item.toolTip = "Return the session to the notch"
        item.image = NSImage(
            systemSymbolName: "inset.filled.tophalf.rectangle",
            accessibilityDescription: "Move to Notch"
        )
        item.target = self
        item.action = #selector(move)
        return item
    }

    @objc private func move() { onMove?() }
}

extension NSToolbarItem.Identifier {
    static let moveToNotch = NSToolbarItem.Identifier("MoveToNotch")
}
