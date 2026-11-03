import AppKit

@MainActor
final class TabRailView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onNew: (() -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?

    private var items: [SessionTabItem] = []
    private var selectedID: UUID?
    private var editingID: UUID?
    private let newTab = NewTabItem()
    private var tracking: NSTrackingArea?
    private var hoverMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        newTab.toolTip = "New Tab (⌘T)"
        newTab.onNew = { [weak self] in self?.onNew?() }
        addSubview(newTab)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let hoverMonitor {
            NSEvent.removeMonitor(hoverMonitor)
            self.hoverMonitor = nil
        }
        guard window != nil else {
            syncHover(at: nil)
            return
        }
        hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.syncHoverFromWindow()
            }
            return event
        }
        syncHoverFromWindow()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        syncHoverFromWindow()
    }

    override func mouseMoved(with event: NSEvent) {
        syncHoverFromWindow()
    }

    override func mouseExited(with event: NSEvent) {
        syncHoverFromWindow()
    }

    private func syncHoverFromWindow() {
        guard let window, !isHidden else {
            syncHover(at: nil)
            return
        }
        let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        syncHover(at: bounds.contains(local) ? local : nil)
    }

    private func syncHover(at point: NSPoint?) {
        for item in items {
            item.setHover(point.map { item.frame.contains($0) } ?? false)
        }
        newTab.setHover(point.map { newTab.frame.contains($0) } ?? false)
    }

    func reload(sessions: [TerminalSession], selected: UUID?) {
        selectedID = selected
        let canClose = sessions.count > 1
        if items.count != sessions.count {
            items.forEach { $0.removeFromSuperview() }
            items.removeAll()
            for session in sessions {
                let item = SessionTabItem()
                item.sessionID = session.id
                item.onSelect = { [weak self] id in self?.onSelect?(id) }
                item.onBeginEdit = { [weak self] id in self?.editingID = id }
                item.onRename = { [weak self] id, name in
                    self?.editingID = nil
                    self?.onRename?(id, name)
                }
                item.onClose = { [weak self] id in self?.onClose?(id) }
                addSubview(item)
                items.append(item)
            }
        }

        for (index, session) in sessions.enumerated() {
            guard items.indices.contains(index) else { continue }
            let item = items[index]
            item.sessionID = session.id
            item.canClose = canClose
            if editingID != session.id {
                item.setTitle(session.tabTitle, selected: session.id == selected)
            } else {
                item.setSelected(session.id == selected)
            }
            item.toolTip = session.cwd ?? session.tabTitle
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 8
        let tabHeight = ChromeMetrics.tabTile
        let width = max(0, bounds.width - pad * 2)
        var y = bounds.maxY - pad - tabHeight
        for item in items {
            item.frame = NSRect(x: pad, y: y, width: width, height: tabHeight)
            y -= tabHeight + ChromeMetrics.tabGap
        }
        newTab.frame = NSRect(x: pad, y: max(pad, y), width: width, height: tabHeight)
    }
}

@MainActor
private final class TabCloseButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        contentTintColor = NSColor.white.withAlphaComponent(0.72)
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        sendAction(on: .leftMouseDown)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class TabTitleField: NSTextField {
    var allowsFocus = false

    override var acceptsFirstResponder: Bool { allowsFocus }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class SessionTabItem: NSView {
    var sessionID = UUID()
    var onSelect: ((UUID) -> Void)?
    var onBeginEdit: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onClose: ((UUID) -> Void)?
    var canClose = false {
        didSet { refreshCloseVisibility() }
    }

    private let label = TabTitleField()
    private let closeButton = TabCloseButton()
    private var selected = false
    private var hovered = false
    private var titleBeforeEdit: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.6

        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.isBordered = false
        label.focusRingType = .none
        label.backgroundColor = .clear
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.cell?.sendsActionOnEndEditing = true
        label.target = self
        label.action = #selector(commitEdit)
        label.delegate = self
        addSubview(label)

        closeButton.toolTip = "Close Tab"
        closeButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)
        paint()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init?(coder: NSCoder) { nil }

    func setTitle(_ text: String, selected: Bool) {
        label.stringValue = text
        setSelected(selected)
    }

    func setSelected(_ selected: Bool) {
        self.selected = selected
        paint()
    }

    func setHover(_ on: Bool) {
        guard hovered != on else { return }
        hovered = on
        refreshCloseVisibility()
        paint()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 6
        let font = label.font ?? NSFont.systemFont(ofSize: 11)
        let textH = ceil(font.boundingRectForFont.height)
        let textY = ((bounds.height - textH) / 2).rounded()
        let insetX: CGFloat = 8
        label.frame = NSRect(
            x: insetX,
            y: textY,
            width: max(0, bounds.width - insetX * 2),
            height: textH
        )
        closeButton.frame = NSRect(
            x: bounds.maxX - 20,
            y: 0,
            width: 20,
            height: bounds.height
        )
        refreshCloseVisibility()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if !closeButton.isHidden, closeButton.frame.contains(local) {
            return closeButton
        }
        if isEditing, label.frame.contains(local) {
            return label
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            beginEdit()
        } else {
            onSelect?(sessionID)
        }
    }

    @objc private func closeTapped() {
        onClose?(sessionID)
    }

    private var isEditing: Bool { label.isEditable }

    private func beginEdit() {
        guard !isEditing else { return }
        onBeginEdit?(sessionID)
        titleBeforeEdit = label.stringValue
        label.allowsFocus = true
        label.isEditable = true
        label.isSelectable = true
        refreshCloseVisibility()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditing else { return }
            self.window?.makeFirstResponder(self.label)
            self.styleFieldEditor()
            self.label.currentEditor()?.selectAll(nil)
        }
    }

    @objc private func commitEdit() {
        guard isEditing else { return }
        let name = label.stringValue
        label.allowsFocus = false
        label.isEditable = false
        label.isSelectable = false
        titleBeforeEdit = nil
        refreshCloseVisibility()
        onRename?(sessionID, name)
    }

    private func refreshCloseVisibility() {
        closeButton.isHidden = !(canClose && hovered && !isEditing)
    }

    private func styleFieldEditor() {
        guard let textView = label.currentEditor() as? NSTextView else { return }
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.94)
        textView.font = label.font
        textView.alignment = .center
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
    }

    private func paint() {
        if selected {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            label.textColor = NSColor.white.withAlphaComponent(0.94)
        } else if hovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            label.textColor = NSColor.white.withAlphaComponent(0.78)
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            label.textColor = NSColor.white.withAlphaComponent(0.62)
        }
    }
}

extension SessionTabItem: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        styleFieldEditor()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitEdit()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            label.stringValue = titleBeforeEdit ?? label.stringValue
            commitEdit()
            return true
        }
        return false
    }
}

@MainActor
private final class NewTabItem: NSView {
    var onNew: (() -> Void)?

    private let icon = NSImageView()
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.6
        icon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        addSubview(icon)
        paint()
    }

    required init?(coder: NSCoder) { nil }

    func setHover(_ on: Bool) {
        guard hovered != on else { return }
        hovered = on
        paint()
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 12
        icon.frame = NSRect(
            x: ((bounds.width - size) / 2).rounded(),
            y: ((bounds.height - size) / 2).rounded(),
            width: size,
            height: size
        )
    }

    override func mouseDown(with event: NSEvent) {
        onNew?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func paint() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(hovered ? 0.12 : 0.06).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.16 : 0.08).cgColor
    }
}
