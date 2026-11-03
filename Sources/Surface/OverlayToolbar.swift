import AppKit

@MainActor
final class OverlayToolbar: NSView {
    var onPin: (() -> Void)?
    var onKick: (() -> Void)?
    var onNew: (() -> Void)?
    var onClose: (() -> Void)?

    private let plusButton: NSButton
    private let closeButton: NSButton
    private let pinButton: NSButton
    private let kickButton: NSButton
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        plusButton = GlassIconButton.make(
            symbol: "plus",
            tooltip: "New Tab (⌘T)",
            target: nil,
            action: #selector(newTapped)
        )
        closeButton = GlassIconButton.make(
            symbol: "xmark",
            tooltip: "Close Tab (⌘W)",
            target: nil,
            action: #selector(closeTapped)
        )
        pinButton = GlassIconButton.make(
            symbol: "pin",
            tooltip: "Pin",
            target: nil,
            action: #selector(pinTapped)
        )
        kickButton = GlassIconButton.make(
            symbol: "macwindow",
            tooltip: "Pop Out",
            target: nil,
            action: #selector(kickTapped)
        )
        super.init(frame: frameRect)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)

        plusButton.target = self
        closeButton.target = self
        pinButton.target = self
        kickButton.target = self

        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = NSColor.white.withAlphaComponent(0.78)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.drawsBackground = false
        titleField.isBezeled = false

        addSubview(plusButton)
        addSubview(closeButton)
        addSubview(titleField)
        addSubview(pinButton)
        addSubview(kickButton)
        closeButton.isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func setPinned(_ pinned: Bool) {
        GlassIconButton.setSymbol(pinButton, pinned ? "pin.fill" : "pin")
        pinButton.toolTip = pinned ? "Unpin" : "Pin"
    }

    func setTitle(_ text: String) {
        titleField.stringValue = text
    }

    func setShowsNewTab(_ show: Bool) {
        plusButton.isHidden = !show
        needsLayout = true
    }

    func setShowsCloseTab(_ show: Bool) {
        closeButton.isHidden = !show
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttons = [plusButton, closeButton, pinButton, kickButton].filter { !$0.isHidden }
        for button in buttons {
            button.sizeToFit()
        }
        let size = max(plusButton.fittingSize.width, plusButton.fittingSize.height, 28)
        let pad: CGFloat = 12
        let y = (bounds.height - size) / 2

        var x = pad
        if !plusButton.isHidden {
            plusButton.frame = NSRect(x: x, y: y, width: size, height: size)
            x = plusButton.frame.maxX + 8
        }
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: x, y: y, width: size, height: size)
            x = closeButton.frame.maxX + 8
        }

        kickButton.frame = NSRect(x: bounds.maxX - size - pad, y: y, width: size, height: size)
        pinButton.frame = NSRect(x: kickButton.frame.minX - size - 8, y: y, width: size, height: size)

        titleField.frame = NSRect(
            x: x + 4,
            y: 8,
            width: max(0, pinButton.frame.minX - (x + 4) - 10),
            height: bounds.height - 16
        )
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func kickTapped() { onKick?() }
    @objc private func newTapped() { onNew?() }
    @objc private func closeTapped() { onClose?() }
}
