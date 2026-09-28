import AppKit

// Editable, resolution-independent source for the macOS app icon.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/StorageMaster.iconset"
let preview = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/StorageMasterIcon.png"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func shaded(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat = 90) {
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}
func shadowed(blur: CGFloat, offset: NSSize, opacity: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x0E2860, alpha: opacity)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}
func ringSegment(start: CGFloat, end: CGFloat, color fill: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: NSPoint(x: 503, y: 554), radius: 137,
                   startAngle: start, endAngle: end, clockwise: true)
    path.lineWidth = 54
    path.lineCapStyle = .butt
    fill.setStroke()
    path.stroke()
}
func sparkle(center: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x, y: center.y + radius))
    path.curve(to: NSPoint(x: center.x + radius, y: center.y),
               controlPoint1: NSPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18),
               controlPoint2: NSPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18))
    path.curve(to: NSPoint(x: center.x, y: center.y - radius),
               controlPoint1: NSPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18),
               controlPoint2: NSPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18))
    path.curve(to: NSPoint(x: center.x - radius, y: center.y),
               controlPoint1: NSPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18),
               controlPoint2: NSPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18))
    path.curve(to: NSPoint(x: center.x, y: center.y + radius),
               controlPoint1: NSPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18),
               controlPoint2: NSPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18))
    path.close()
    NSColor.white.setFill()
    path.fill()
}
func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = rounded(NSRect(x: 64, y: 64, width: 896, height: 896), 198)
    shadowed(blur: 21, offset: NSSize(width: 0, height: -13), opacity: 0.23) {
        color(0x3568E5).setFill(); tile.fill()
    }
    shaded(tile, colors: [color(0x2455C9), color(0x3D74EE), color(0x81ACFF)], angle: 70)
    color(0xFFFFFF, alpha: 0.22).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    let chassis = rounded(NSRect(x: 232, y: 205, width: 560, height: 578), 82)
    shadowed(blur: 32, offset: NSSize(width: 0, height: -22), opacity: 0.3) {
        color(0xB7C9E8).setFill(); chassis.fill()
    }
    shaded(chassis, colors: [color(0xB6C9EA), color(0xEBF2FF), color(0xFFFFFF)])
    let face = rounded(NSRect(x: 232, y: 274, width: 560, height: 509), 82)
    shaded(face, colors: [color(0xE9F0FD), color(0xFFFFFF)])
    color(0xFFFFFF, alpha: 0.75).setStroke()
    face.lineWidth = 3; face.stroke()

    let ring = NSBezierPath(ovalIn: NSRect(x: 366, y: 417, width: 274, height: 274))
    ring.lineWidth = 54
    color(0xDDE7F8).setStroke(); ring.stroke()
    ringSegment(start: 88, end: -119, color: color(0x4175E6))
    ringSegment(start: -125, end: -204, color: color(0x39B5AA))
    ringSegment(start: -210, end: -251, color: color(0x9B8ADB))
    let spindle = NSBezierPath(ovalIn: NSRect(x: 476, y: 527, width: 54, height: 54))
    shaded(spindle, colors: [color(0xC5D3E8), color(0xEFF4FC)])
    color(0xA5B9D8).setStroke(); spindle.lineWidth = 2; spindle.stroke()

    color(0x6C87B8, alpha: 0.7).setFill()
    rounded(NSRect(x: 299, y: 247, width: 154, height: 12), 6).fill()
    color(0xE3FFF6).setFill()
    NSBezierPath(ovalIn: NSRect(x: 686, y: 237, width: 28, height: 28)).fill()
    color(0x2CAF90).setFill()
    NSBezierPath(ovalIn: NSRect(x: 692, y: 243, width: 16, height: 16)).fill()
    shadowed(blur: 11, offset: NSSize(width: 0, height: -5), opacity: 0.15) {
        sparkle(center: NSPoint(x: 786, y: 800), radius: 66)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size * scale).write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
try render(1024).write(to: URL(fileURLWithPath: preview))
print("Icon PNG: \(preview)")
print("Iconset: \(output)")
