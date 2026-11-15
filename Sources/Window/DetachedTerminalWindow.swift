import AppKit

@MainActor
final class DetachedTerminalWindow: NSWindow {
    var onMoveToNotch: (() -> Void)?
    var onOpenSettings: (() -> Void)?

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

    func applyWash(_ wash: TerminalPalette) {
        let color = wash.background
        backgroundColor = color
        host.layer?.backgroundColor = color.cgColor
        appearance = NSAppearance(named: wash.isLight ? .aqua : .darkAqua)
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
        ToolbarShim.shared.onSettings = { [weak self] in self?.onOpenSettings?() }
        return toolbar
    }
}

@MainActor
private final class ToolbarShim: NSObject, NSToolbarDelegate {
    static let shared = ToolbarShim()
    var onMove: (() -> Void)?
    var onSettings: (() -> Void)?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .openSettings, .moveToNotch]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .openSettings, .moveToNotch]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == .openSettings {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(openSettings)
            return item
        }
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
    @objc private func openSettings() { onSettings?() }
}

extension NSToolbarItem.Identifier {
    static let moveToNotch = NSToolbarItem.Identifier("MoveToNotch")
    static let openSettings = NSToolbarItem.Identifier("OpenSettings")
}
