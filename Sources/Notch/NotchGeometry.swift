import AppKit

enum ChromeMetrics {
    static let expandedWidth: CGFloat = 780
    static let expandedHeight: CGFloat = 420
    static let toolbarHeight: CGFloat = 48
    static let tabRailWidth: CGFloat = 108
    static let tabBarHeight: CGFloat = 32
    static let tabTile: CGFloat = 26
    static let tabGap: CGFloat = 6
    static let tabMinWidth: CGFloat = 88
    static let tabMaxWidth: CGFloat = 168
    static let bottomRadius: CGFloat = 30
    static let busyExtra: CGFloat = 24
    static let hitSlop: CGFloat = 4
    static let contentInset: CGFloat = 10
    static let shadowLeft: CGFloat = 56
    static let shadowRight: CGFloat = 56
    static let shadowBottom: CGFloat = 68
}

struct NotchGeometry: Equatable {
    var screen: NSScreen
    var notch: NSRect
    var hasNotch: Bool

    var menuBarHeight: CGFloat { notch.height }

    func hitTarget() -> NSRect {
        notch.insetBy(dx: 0, dy: -ChromeMetrics.hitSlop / 2)
            .offsetBy(dx: 0, dy: -ChromeMetrics.hitSlop / 2)
    }

    func busyIsland() -> NSRect {
        let core = notch.insetBy(dx: -ChromeMetrics.busyExtra, dy: 0)
            .offsetBy(dx: 0, dy: -4)
            .union(NSRect(
                x: notch.minX - ChromeMetrics.busyExtra,
                y: notch.minY - 6,
                width: notch.width + ChromeMetrics.busyExtra * 2,
                height: notch.height + 6
            ))
        return NSRect(
            x: core.minX - 16,
            y: core.minY - 20,
            width: core.width + 32,
            height: core.height + 20
        )
    }

    func expandedFrame() -> NSRect {
        let screenFrame = screen.frame
        let cardW = min(max(ChromeMetrics.expandedWidth, screenFrame.width * 0.5), 980)
        let cardH = ChromeMetrics.expandedHeight
        let width = cardW + ChromeMetrics.shadowLeft + ChromeMetrics.shadowRight
        let height = cardH + ChromeMetrics.shadowBottom
        var x = notch.midX - width / 2
        x = min(max(x, screenFrame.minX), screenFrame.maxX - width)
        let y = screenFrame.maxY - cardH - ChromeMetrics.shadowBottom
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func fallbackPill() -> NSRect {
        let screenFrame = screen.frame
        let height: CGFloat = 28
        let width: CGFloat = 180
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    static func resolve() -> NotchGeometry {
        let screens = NSScreen.screens
        for screen in screens {
            if let geo = geometry(for: screen), geo.hasNotch {
                return geo
            }
        }
        let screen = NSScreen.main ?? screens[0]
        return geometry(for: screen) ?? NotchGeometry(
            screen: screen,
            notch: screen.frame,
            hasNotch: false
        )
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry? {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let menuBarHeight = max(frame.maxY - visible.maxY, 24)

        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea

        if let left, let right, left.width > 0, right.width > 0, right.minX - left.maxX > 40 {
            let notch = NSRect(
                x: left.maxX,
                y: frame.maxY - menuBarHeight,
                width: right.minX - left.maxX,
                height: menuBarHeight
            )
            return NotchGeometry(screen: screen, notch: notch, hasNotch: true)
        }

        let pill = NSRect(
            x: frame.midX - 90,
            y: frame.maxY - menuBarHeight,
            width: 180,
            height: menuBarHeight
        )
        return NotchGeometry(screen: screen, notch: pill, hasNotch: false)
    }
}
