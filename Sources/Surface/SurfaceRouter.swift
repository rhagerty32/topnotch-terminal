import AppKit

enum SurfaceMode {
    case collapsed
    case expanded
    case pinned
    case windowed
}

@MainActor
final class SurfaceRouter: NSObject, NSWindowDelegate {
    let store: SessionStore
    let notch = NotchPanelController()
    let workspace: WorkspaceView

    private(set) var mode: SurfaceMode = .collapsed
    private var windowController: DetachedTerminalWindow?
    private var geometry = NotchGeometry.resolve()
    private var keyMonitor: Any?
    private var hoverInside = false

    init(store: SessionStore) {
        self.store = store
        workspace = WorkspaceView(store: store)
        super.init()
        notch.chrome.pinWorkspace(toCardSize: NotchChromeView.cardSize(forPanel: geometry.expandedFrame()))
        workspace.autoresizingMask = [.width, .height]
        notch.chrome.workspaceHolder.addSubview(workspace)
        workspace.frame = notch.chrome.workspaceHolder.bounds

        notch.chrome.toolbar.onPin = { [weak self] in self?.togglePin() }
        notch.chrome.toolbar.onKick = { [weak self] in self?.kickOut() }
        notch.chrome.toolbar.onNew = { [weak self] in self?.addTab() }
        notch.chrome.toolbar.onClose = { [weak self] in self?.closeTab() }
        notch.onHoverEnter = { [weak self] in self?.hoverEntered() }
        notch.onHoverExit = { [weak self] in self?.hoverExited() }
        notch.onBusyClick = { [weak self] in self?.focusWindowedIfNeeded() }
        notch.onUserInteract = { [weak self] in
            self?.notch.focusTerminal(self?.store.selected?.hostView)
        }

        store.onChange = { [weak self] in
            guard let self else { return }
            self.workspace.reload(focus: false)
            self.refreshToolbarOnly()
            if self.mode == .collapsed {
                self.refreshCollapsedPresence()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let swallow = MainActor.assumeIsolated {
                self.handleKey(event)
            }
            return swallow ? nil : event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.geometry = NotchGeometry.resolve()
                self?.refreshChrome()
            }
        }

        apply(mode: .collapsed, reason: "launch")
        notch.orderFront()
    }

    func hoverEntered() {
        hoverInside = true
        switch mode {
        case .collapsed:
            apply(mode: .expanded, reason: "hover")
        case .windowed:
            focusWindowedIfNeeded()
        default:
            break
        }
    }

    /// Raycast / `open` / URL: show the live surface and put the cursor in the terminal.
    func summon() {
        switch mode {
        case .windowed:
            focusWindowedIfNeeded()
        case .collapsed:
            hoverInside = false
            apply(mode: .expanded, reason: "summon")
        case .expanded, .pinned:
            notch.setChromeInteractive(true, becomeKey: true)
            notch.orderFront()
            workspace.reload(focus: true)
            notch.focusTerminal(store.selected?.hostView)
        }
    }

    func hoverExited() {
        guard hoverInside else { return }
        hoverInside = false
        guard mode == .expanded else { return }
        apply(mode: .collapsed, reason: "leave")
    }

    func togglePin() {
        switch mode {
        case .pinned:
            apply(mode: .expanded, reason: "unpin")
        case .expanded, .collapsed:
            apply(mode: .pinned, reason: "pin")
        case .windowed:
            break
        }
    }

    func addTab() {
        store.addTab()
    }

    func closeTab() {
        store.closeSelected()
    }

    func kickOut() {
        guard mode != .windowed else { return }
        apply(mode: .windowed, reason: "kick")
    }

    func kickBack() {
        guard mode == .windowed else { return }
        hoverInside = false
        apply(mode: .expanded, reason: "kickback")
    }

    func handleIPC(_ command: IPCCommand) {
        switch command {
        case .kick: kickOut()
        case .kickback: kickBack()
        case .focus: summon()
        }
    }

    func shutdown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        store.terminateAll()
        windowController?.orderOut(nil)
        notch.orderOut()
    }

    private func apply(mode newMode: SurfaceMode, reason: String) {
        _ = reason
        let previous = mode
        mode = newMode
        geometry = NotchGeometry.resolve()

        switch newMode {
        case .collapsed, .expanded, .pinned:
            if previous == .windowed {
                reparentToNotch()
            }
            NSApp.setActivationPolicy(.accessory)
            notch.orderFront()
            windowController?.orderOut(nil)
        case .windowed:
            NSApp.setActivationPolicy(.regular)
            reparentToWindow()
            NSApp.activate(ignoringOtherApps: true)
        }

        refreshChrome(from: previous)
    }

    private func refreshChrome(from previous: SurfaceMode? = nil) {
        geometry = NotchGeometry.resolve()
        let busy = store.isAnyBusy
        let title = store.selected.map { session in
            if let cwd = session.cwd { return "\(session.title) — \(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" }
            return session.title
        } ?? "TopNotch Terminal"

        let changed = previous != nil && previous != mode
        let opening = changed && (previous == .collapsed || previous == .windowed)
            && (mode == .expanded || mode == .pinned)
        let closing = changed && (previous == .expanded || previous == .pinned)
            && mode == .collapsed
        refreshToolbarOnly()

        switch mode {
        case .collapsed:
            notch.setChromeInteractive(false, becomeKey: false)
            notch.panel.resignKey()
            notch.chrome.toolbar.setPinned(false)
            if closing {
                notch.collapse(
                    to: busy ? geometry.busyIsland() : geometry.hitTarget(),
                    notch: geometry.notch,
                    busy: busy,
                    animated: true
                )
            } else if busy {
                notch.showBusyIsland(at: geometry.busyIsland(), animated: true)
            } else {
                notch.hideAll(at: geometry.hitTarget())
            }
            notch.orderFront()
            notch.panel.setAccessibilityElement(busy)
            notch.panel.setAccessibilityLabel(busy ? "TopNotch Terminal, job running" : nil)
        case .expanded:
            notch.setChromeInteractive(true, becomeKey: true)
            notch.chrome.toolbar.setPinned(false)
            if opening {
                notch.expand(to: geometry.expandedFrame(), notch: geometry.notch, animated: true)
            } else {
                notch.keepExpanded(at: geometry.expandedFrame())
            }
            notch.orderFront()
            workspace.reload(focus: true)
            notch.focusTerminal(store.selected?.hostView)
        case .pinned:
            notch.setChromeInteractive(true, becomeKey: true)
            notch.chrome.toolbar.setPinned(true)
            if opening {
                notch.expand(to: geometry.expandedFrame(), notch: geometry.notch, animated: true)
            } else {
                notch.keepExpanded(at: geometry.expandedFrame())
            }
            notch.orderFront()
            workspace.reload(focus: true)
            notch.focusTerminal(store.selected?.hostView)
        case .windowed:
            notch.setChromeInteractive(false, becomeKey: false)
            if busy {
                notch.showBusyIsland(at: geometry.busyIsland(), animated: false)
                notch.orderFront()
            } else {
                notch.hideAll(at: geometry.hitTarget())
                notch.orderOut()
            }
            windowController?.title = title
            workspace.reload(focus: true)
            windowController?.makeKeyAndOrderFront(nil)
            windowController?.makeFirstResponder(store.selected?.hostView)
        }
        workspace.layoutSubtreeIfNeeded()
    }

    private func refreshCollapsedPresence() {
        let busy = store.isAnyBusy
        if busy {
            notch.showBusyIsland(at: geometry.busyIsland(), animated: true)
        } else {
            notch.hideAll(at: geometry.hitTarget())
        }
        notch.orderFront()
    }

    private func refreshToolbarOnly() {
        let title = store.selected.map { session in
            if let cwd = session.cwd {
                return "\(session.title) — \(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
            }
            return session.title
        } ?? "TopNotch Terminal"
        let many = store.sessions.count > 1
        notch.chrome.toolbar.setTitle(title)
        notch.chrome.toolbar.setShowsNewTab(true)
        notch.chrome.toolbar.setShowsCloseTab(many)
        notch.chrome.toolbar.setPinned(mode == .pinned)
        if mode == .windowed {
            windowController?.title = title
        }
    }

    private func reparentToWindow() {
        if windowController == nil {
            let window = DetachedTerminalWindow()
            window.delegate = self
            window.onMoveToNotch = { [weak self] in self?.kickBack() }
            windowController = window
        }
        workspace.removeFromSuperview()
        windowController?.embed(workspace)
        windowController?.setFrame(
            NSRect(x: 0, y: 0, width: 760, height: 480),
            display: true
        )
        windowController?.center()
        windowController?.makeKeyAndOrderFront(nil)
    }

    private func reparentToNotch() {
        workspace.removeFromSuperview()
        notch.chrome.workspaceHolder.addSubview(workspace)
        workspace.frame = notch.chrome.workspaceHolder.bounds
        workspace.autoresizingMask = [.width, .height]
        windowController?.orderOut(nil)
    }

    private func focusWindowedIfNeeded() {
        guard mode == .windowed else { return }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.makeKeyAndOrderFront(nil)
        windowController?.makeFirstResponder(store.selected?.hostView)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode
        let mods = flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if keyCode == 53, mods.isEmpty, !store.isAnyBusy {
            switch mode {
            case .expanded, .pinned:
                apply(mode: .collapsed, reason: "escape")
                return true
            default:
                break
            }
        }
        if flags.contains(.command), chars == "t" {
            store.addTab()
            return true
        }
        if flags.contains(.command), chars == "w" {
            store.closeSelected()
            return true
        }
        if flags.contains(.control), keyCode == 48 {
            store.cycle(forward: !flags.contains(.shift))
            return true
        }
        if flags.contains(.command), let n = Int(chars), (1...9).contains(n) {
            store.selectIndex(n - 1)
            return true
        }
        if let view = store.selected?.hostView, isTerminalFocused(view) {
            if KeyboardSelection.handle(event, in: view) { return true }
            if KeyboardSelection.handleEditing(event, in: view) { return true }
        } else if KeyboardSelection.paste(event, into: nil) {
            return true
        }
        return sendCocoaFieldKeys(flags: flags, keyCode: keyCode)
    }

    private func isTerminalFocused(_ view: NSView) -> Bool {
        let window: NSWindow? = mode == .windowed ? windowController : notch.panel
        guard let window, window.isKeyWindow else { return false }
        guard let responder = window.firstResponder else { return false }
        if let textView = responder as? NSTextView, textView.isFieldEditor { return false }
        if responder is NSTextField { return false }
        return responder === view || (responder as? NSView)?.isDescendant(of: view) == true
    }

    private func sendCocoaFieldKeys(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        guard let bytes = CocoaFieldKeys.bytes(flags: flags, keyCode: keyCode) else { return false }
        guard let view = store.selected?.hostView, isTerminalFocused(view) else { return false }
        view.send(bytes)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        kickBack()
        return false
    }
}
