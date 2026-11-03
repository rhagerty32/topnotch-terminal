#!/usr/bin/env swift
import AppKit

let pointWidth: CGFloat = 720
let pointHeight: CGFloat = 440
let scale: CGFloat = 2
let pixelWidth = Int(pointWidth * scale)
let pixelHeight = Int(pointHeight * scale)

let image = NSImage(size: NSSize(width: pointWidth, height: pointHeight))
image.lockFocusFlipped(true)

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

let canvas = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
NSGradient(starting: color(0x141414), ending: color(0x0B0B0B))?.draw(in: canvas, angle: 90)

let chassis = CGRect(x: 18, y: 10, width: 684, height: 420)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0x1C1C1E).setFill()
rounded(chassis, 26).fill()
NSShadow().set()

color(0x3A3A3C, alpha: 0.55).setStroke()
let rim = rounded(chassis.insetBy(dx: 0.6, dy: 0.6), 25.4)
rim.lineWidth = 1.2
rim.stroke()

let bezel = chassis.insetBy(dx: 9, dy: 9)
color(0x000000).setFill()
rounded(bezel, 18).fill()

let screen = CGRect(x: bezel.minX + 7, y: bezel.minY + 7, width: bezel.width - 14, height: bezel.height - 22)
NSGraphicsContext.current?.saveGraphicsState()
rounded(screen, 12).addClip()
NSGradient(colors: [
    color(0xB9D4F0),
    color(0xE7EEF7),
    color(0xF7F4EE)
], atLocations: [0, 0.45, 1], colorSpace: .sRGB)?.draw(in: screen, angle: 115)
NSGraphicsContext.current?.restoreGraphicsState()

let notchW: CGFloat = 248
let notchH: CGFloat = 126
let notch = CGRect(x: (pointWidth - notchW) / 2, y: bezel.minY, width: notchW, height: notchH)
color(0x000000).setFill()
let notchPath = NSBezierPath()
notchPath.move(to: CGPoint(x: notch.minX, y: notch.minY))
notchPath.line(to: CGPoint(x: notch.maxX, y: notch.minY))
notchPath.line(to: CGPoint(x: notch.maxX, y: notch.maxY - 24))
notchPath.appendArc(
    withCenter: CGPoint(x: notch.maxX - 24, y: notch.maxY - 24),
    radius: 24,
    startAngle: 0,
    endAngle: 90
)
notchPath.line(to: CGPoint(x: notch.minX + 24, y: notch.maxY))
notchPath.appendArc(
    withCenter: CGPoint(x: notch.minX + 24, y: notch.maxY - 24),
    radius: 24,
    startAngle: 90,
    endAngle: 180
)
notchPath.close()
notchPath.fill()

color(0xFFFFFF, alpha: 0.10).setStroke()
let seam = NSBezierPath()
seam.lineWidth = 1
seam.move(to: CGPoint(x: notch.minX + 20, y: notch.maxY - 0.5))
seam.line(to: CGPoint(x: notch.maxX - 20, y: notch.maxY - 0.5))
seam.stroke()

func chevron(y: CGFloat, alpha: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = 2.4
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: CGPoint(x: 360 - 12, y: y + 8))
    path.line(to: CGPoint(x: 360, y: y))
    path.line(to: CGPoint(x: 360 + 12, y: y + 8))
    color(0x111827, alpha: alpha).setStroke()
    path.stroke()
}

chevron(y: 186, alpha: 0.22)
chevron(y: 170, alpha: 0.40)

let caption = "Drag into the notch to install"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: color(0x1F2937, alpha: 0.62)
]
let capSize = caption.size(withAttributes: attrs)
caption.draw(
    at: CGPoint(x: (pointWidth - capSize.width) / 2, y: 372),
    withAttributes: attrs
)

image.unlockFocus()

let outURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? FileManager.default.currentDirectoryPath + "/Resources/dmg/background.png")
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let reps = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
reps.size = NSSize(width: pointWidth, height: pointHeight)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: reps)
image.draw(in: CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = reps.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: outURL)
print("Wrote \(outURL.path)")
