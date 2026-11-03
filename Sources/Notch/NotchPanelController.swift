import AppKit
import QuartzCore

@MainActor
final class NotchPanel: NSPanel {
    var allowKey = false
    var onUserInteract: (() -> Void)?

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let hit = contentView?.hitTest(event.locationInWindow)
            if Self.shouldRefocusTerminal(after: hit) {
                onUserInteract?()
            }
        }
        super.sendEvent(event)
    }

    private static func shouldRefocusTerminal(after hit: NSView?) -> Bool {
        guard let hit else { return true }
        if hit is NSControl { return false }
        var view: NSView? = hit
        while let current = view {
            if current is TabRailView || current is OverlayToolbar { return false }
            view = current.superview
        }
        return true
    }
}

@MainActor
final class NotchChromeView: NSView {
    let toolbar = OverlayToolbar()
    let workspaceHolder = NSView(frame: .zero)

    private let bloom = NSView(frame: .zero)
    private let shadowCaster = NSView(frame: .zero)
    private let card = NSView(frame: .zero)
    private let hairline = NSView(frame: .zero)

    var showsChrome = false {
        didSet { applyVisibility() }
    }
    var showsBusyIsland = false {
        didSet { applyVisibility() }
    }

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onMouseDown: (() -> Void)?

    var cardFrame: NSRect { card.frame }
    var restingCardFrame: NSRect { currentCardFrame() }
    var hoverHost: NSView { (showsChrome || showsBusyIsland) ? card : self }

    override var isFlipped: Bool { false }

    private let spring = RectSpring()
    private var drivingCardFrame = false
    /// Expanded workspace size. The card clips this during the spring — never
    /// shrink the holder to the live card or SwiftTerm will WINCH every frame
    /// and zsh will reprint the prompt as a staircase.
    private var stableWorkspaceSize = NotchChromeView.workspaceSize(
        forCard: NSSize(width: ChromeMetrics.expandedWidth, height: ChromeMetrics.expandedHeight)
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        configureShadowHost(bloom)
        configureShadowHost(shadowCaster)

        card.wantsLayer = true
        card.autoresizesSubviews = false
        card.clipsToBounds = true
        card.appearance = NSAppearance(named: .darkAqua)
        card.layer?.backgroundColor = NSColor.black.cgColor
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.8
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        for view in [bloom, shadowCaster, card] {
            addSubview(view)
        }

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        hairline.layer?.cornerRadius = 0.5

        workspaceHolder.wantsLayer = true
        workspaceHolder.autoresizingMask = []
        workspaceHolder.clipsToBounds = true
        workspaceHolder.layer?.backgroundColor = NSColor.black.cgColor
        workspaceHolder.layer?.cornerRadius = 0
        workspaceHolder.layer?.masksToBounds = true
        workspaceHolder.layer?.borderWidth = 0

        toolbar.isHidden = true
        workspaceHolder.isHidden = true
        card.addSubview(workspaceHolder)
        card.addSubview(hairline)
        card.addSubview(toolbar)
        toolbar.layer?.zPosition = 10

        applyVisibility()
        layoutInterior()
    }

    static func workspaceSize(forCard cardSize: NSSize) -> NSSize {
        let inset = ChromeMetrics.contentInset
        return NSSize(
            width: max(1, cardSize.width - inset * 2),
            height: max(1, cardSize.height - ChromeMetrics.toolbarHeight - inset - 4)
        )
    }

    static func cardSize(forPanel frame: NSRect) -> NSSize {
        NSSize(
            width: max(1, frame.width - ChromeMetrics.shadowLeft - ChromeMetrics.shadowRight),
            height: max(1, frame.height - ChromeMetrics.shadowBottom)
        )
    }

    func pinWorkspace(toCardSize cardSize: NSSize) {
        let next = Self.workspaceSize(forCard: cardSize)
        guard next != stableWorkspaceSize else {
            layoutInterior()
            return
        }
        stableWorkspaceSize = next
        layoutInterior()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if showsChrome || showsBusyIsland {
            guard card.frame.contains(point) else { return nil }
        }
        return super.hitTest(point) ?? (showsChrome || showsBusyIsland ? card : self)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverExit?()
    }

    override func mouseDown(with event: NSEvent) {
        if showsBusyIsland, !showsChrome {
            onMouseDown?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func layout() {
        super.layout()
        if !drivingCardFrame {
            applyCardFrame(currentCardFrame())
        }
        layoutInterior()
    }

    func prepareDriven() {
        spring.cancel()
        drivingCardFrame = true
    }

    func animateCard(from start: NSRect, to end: NSRect, expanding: Bool, completion: (() -> Void)? = nil) {
        drivingCardFrame = true
        applyCardFrame(start)
        layoutInterior()
        let minW = min(start.width, end.width)
        let spanW = max(1, abs(end.width - start.width))
        spring.animate(from: start, to: end, expanding: expanding) { [weak self] rect in
            guard let self else { return }
            self.applyCardFrame(rect)
            self.layoutInterior()
            let progress = (rect.width - minW) / spanW
            let reveal = expanding
                ? min(1, max(0, (progress - 0.18) / 0.5))
                : min(1, max(0, (progress - 0.12) / 0.45))
            self.workspaceHolder.alphaValue = reveal
            self.toolbar.alphaValue = reveal
            self.hairline.alphaValue = reveal
        } completion: { [weak self] in
            guard let self else { return }
            self.drivingCardFrame = false
            self.applyCardFrame(end)
            self.layoutInterior()
            self.workspaceHolder.alphaValue = 1
            self.toolbar.alphaValue = expanding ? 1 : 0
            self.hairline.alphaValue = expanding ? 1 : 0
            completion?()
        }
    }

    func resetMotion() {
        spring.cancel()
        drivingCardFrame = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in [bloom, shadowCaster, card] {
            view.layer?.removeAllAnimations()
            view.layer?.transform = CATransform3DIdentity
            view.layer?.opacity = 1
        }
        CATransaction.commit()
    }

    private func applyCardFrame(_ rect: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloom.frame = rect
        shadowCaster.frame = rect
        card.frame = rect
        applyShape()
        CATransaction.commit()
    }

    private func layoutInterior() {
        toolbar.frame = NSRect(
            x: 0,
            y: card.bounds.maxY - ChromeMetrics.toolbarHeight,
            width: card.bounds.width,
            height: ChromeMetrics.toolbarHeight
        )
        hairline.frame = NSRect(
            x: 18,
            y: toolbar.frame.minY,
            width: max(0, card.bounds.width - 36),
            height: 1
        )
        let inset = ChromeMetrics.contentInset
        let workspaceFrame = NSRect(
            x: inset,
            y: inset,
            width: stableWorkspaceSize.width,
            height: stableWorkspaceSize.height
        )
        if workspaceHolder.frame != workspaceFrame {
            workspaceHolder.frame = workspaceFrame
        }
    }

    private func currentCardFrame() -> NSRect {
        if showsChrome {
            return NSRect(
                x: ChromeMetrics.shadowLeft,
                y: ChromeMetrics.shadowBottom,
                width: max(0, bounds.width - ChromeMetrics.shadowLeft - ChromeMetrics.shadowRight),
                height: max(0, bounds.height - ChromeMetrics.shadowBottom)
            )
        }
        if showsBusyIsland {
            return NSRect(
                x: 16,
                y: 18,
                width: max(0, bounds.width - 32),
                height: max(0, bounds.height - 18)
            )
        }
        return bounds
    }

    private func applyShape() {
        let radius = showsChrome ? ChromeMetrics.bottomRadius : (showsBusyIsland ? 16 : 0)
        let corners: CACornerMask = showsChrome
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        for view in [card, shadowCaster, bloom] {
            view.layer?.cornerRadius = radius
            view.layer?.maskedCorners = corners
            view.layer?.cornerCurve = .continuous
        }

        if showsChrome {
            applyShadow(
                on: bloom,
                opacity: 0.32,
                radius: 56,
                offset: CGSize(width: 0, height: -18),
                pathRadius: radius
            )
            applyShadow(
                on: shadowCaster,
                opacity: 0.55,
                radius: 22,
                offset: CGSize(width: 0, height: -8),
                pathRadius: radius
            )
        } else if showsBusyIsland {
            applyShadow(
                on: bloom,
                opacity: 0.18,
                radius: 20,
                offset: CGSize(width: 0, height: -6),
                pathRadius: radius
            )
            applyShadow(
                on: shadowCaster,
                opacity: 0.32,
                radius: 10,
                offset: CGSize(width: 0, height: -3),
                pathRadius: radius
            )
        } else {
            bloom.layer?.shadowOpacity = 0
            bloom.layer?.shadowPath = nil
            shadowCaster.layer?.shadowOpacity = 0
            shadowCaster.layer?.shadowPath = nil
        }
    }

    private func applyShadow(
        on view: NSView,
        opacity: Float,
        radius: CGFloat,
        offset: CGSize,
        pathRadius: CGFloat
    ) {
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = opacity
        view.layer?.shadowRadius = radius
        view.layer?.shadowOffset = offset
        view.layer?.shadowPath = CGPath(
            roundedRect: view.bounds,
            cornerWidth: pathRadius,
            cornerHeight: pathRadius,
            transform: nil
        )
    }

    private func configureShadowHost(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = false
    }

    private func applyVisibility() {
        let visible = showsChrome || showsBusyIsland
        card.isHidden = !visible
        shadowCaster.isHidden = !visible
        bloom.isHidden = !visible
        toolbar.isHidden = !showsChrome
        hairline.isHidden = !showsChrome
        workspaceHolder.isHidden = !showsChrome
        if showsChrome, !drivingCardFrame {
            toolbar.alphaValue = 1
            hairline.alphaValue = 1
            workspaceHolder.alphaValue = 1
        }
        needsLayout = true
        needsDisplay = true
    }
}

@MainActor
final class NotchPanelController: NSObject {
    let panel: NotchPanel
    let chrome = NotchChromeView()
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onBusyClick: (() -> Void)?
    var onUserInteract: (() -> Void)? {
        get { panel.onUserInteract }
        set { panel.onUserInteract = newValue }
    }

    private var tracking: NSTrackingArea?
    private var trackingHost: NSView?
    private var enterWork: DispatchWorkItem?
    private var exitWork: DispatchWorkItem?
    private var motionGeneration = 0

    override init() {
        panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.mainMenu.rawValue) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.contentView = chrome
        panel.ignoresMouseEvents = false
        chrome.postsFrameChangedNotifications = true
        chrome.onHoverEnter = { [weak self] in self?.scheduleEnter() }
        chrome.onHoverExit = { [weak self] in self?.scheduleExit() }
        chrome.onMouseDown = { [weak self] in self?.onBusyClick?() }
        installTracking()
    }

    func setChromeInteractive(_ interactive: Bool, becomeKey: Bool) {
        panel.allowKey = interactive
        var mask: NSWindow.StyleMask = [.borderless, .fullSizeContentView]
        if !interactive {
            mask.insert(.nonactivatingPanel)
        }
        if panel.styleMask != mask {
            panel.styleMask = mask
        }
        guard becomeKey, interactive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.allowKey else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    func focusTerminal(_ view: NSView?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.allowKey else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            if let view {
                self.panel.makeFirstResponder(view)
            }
        }
    }

    func expand(to frame: NSRect, notch: NSRect, animated: Bool) {
        motionGeneration += 1
        let continuing = chrome.showsChrome
        let live = chrome.cardFrame
        chrome.pinWorkspace(toCardSize: NotchChromeView.cardSize(forPanel: frame))
        chrome.prepareDriven()
        chrome.showsBusyIsland = false
        chrome.showsChrome = true
        panel.setFrame(frame, display: true)
        chrome.layoutSubtreeIfNeeded()

        let dest = chrome.restingCardFrame
        let seed = Self.seedCardRect(notch: notch, dest: dest)
        let from = continuing && live.width > 20 ? live : seed
        if animated {
            chrome.animateCard(from: from, to: dest, expanding: true)
        } else {
            chrome.resetMotion()
            chrome.needsLayout = true
        }
        installTracking()
    }

    func collapse(to frame: NSRect, notch: NSRect, busy: Bool, animated: Bool) {
        motionGeneration += 1
        let generation = motionGeneration
        let dest = chrome.restingCardFrame
        let seed = Self.seedCardRect(notch: notch, dest: dest)
        let start = chrome.cardFrame
        let finish = { [weak self] in
            guard let self, self.motionGeneration == generation else { return }
            self.chrome.resetMotion()
            self.chrome.showsChrome = false
            self.chrome.showsBusyIsland = busy
            self.panel.setFrame(frame, display: true)
            self.chrome.layoutSubtreeIfNeeded()
            self.installTracking()
        }
        guard animated, chrome.showsChrome else {
            finish()
            return
        }
        chrome.animateCard(from: start, to: seed, expanding: false, completion: finish)
    }

    private static func seedCardRect(notch: NSRect, dest: NSRect) -> NSRect {
        let w = max(notch.width, 140)
        let h = max(notch.height, 30)
        return NSRect(x: dest.midX - w / 2, y: dest.maxY - h, width: w, height: h)
    }

    func showBusyIsland(at frame: NSRect, animated: Bool) {
        chrome.resetMotion()
        chrome.showsChrome = false
        chrome.showsBusyIsland = true
        Motion.run(animated: animated, expanding: true, duration: 0.42) {
            self.panel.animator().setFrame(frame, display: true)
        } completion: { [weak self] in
            self?.installTracking()
        }
        chrome.needsLayout = true
        installTracking()
    }

    func hideAll(at frame: NSRect) {
        chrome.resetMotion()
        chrome.showsChrome = false
        chrome.showsBusyIsland = false
        panel.setFrame(frame, display: true)
        installTracking()
    }

    func keepExpanded(at frame: NSRect) {
        chrome.showsBusyIsland = false
        chrome.showsChrome = true
        chrome.pinWorkspace(toCardSize: NotchChromeView.cardSize(forPanel: frame))
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            chrome.layoutSubtreeIfNeeded()
            installTracking()
        }
    }

    func orderFront() {
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel.orderOut(nil)
    }

    private func installTracking() {
        let host = chrome.hoverHost
        if trackingHost === host, tracking != nil {
            return
        }
        if let tracking, let trackingHost {
            trackingHost.removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: chrome,
            userInfo: nil
        )
        host.addTrackingArea(area)
        tracking = area
        trackingHost = host
    }

    private func scheduleEnter() {
        exitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onHoverEnter?()
        }
        enterWork?.cancel()
        enterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.enterDelay, execute: work)
    }

    private func scheduleExit() {
        enterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onHoverExit?()
        }
        exitWork?.cancel()
        exitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.leaveDelay, execute: work)
    }
}
