import AppKit

@MainActor
enum GlassIconButton {
    static func make(
        symbol: String,
        tooltip: String,
        target: AnyObject?,
        action: Selector
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        let button = NSButton(image: image ?? NSImage(), target: target, action: action)
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = true
        button.toolTip = tooltip
        button.focusRingType = .exterior
        button.controlSize = .regular
        button.appearance = NSAppearance(named: .darkAqua)
        applyGlass(to: button)
        return button
    }

    static func makeText(
        _ title: String,
        tooltip: String,
        target: AnyObject?,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.toolTip = tooltip
        button.focusRingType = .exterior
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        button.appearance = NSAppearance(named: .darkAqua)
        applyGlass(to: button)
        return button
    }

    static func setSymbol(_ button: NSButton, _ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.toolTip)
        image?.isTemplate = true
        button.image = image
    }

    static func applyGlass(to button: NSButton) {
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.borderShape = .circle
        } else {
            button.bezelStyle = .circular
        }
    }
}
