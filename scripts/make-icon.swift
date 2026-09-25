import AppKit

// Resolution-independent icon artwork. Geometry is expressed on a 1024-point canvas.
func drawIcon() {
    let tile = NSBezierPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    NSGradient(colors: [
        NSColor(srgbRed: 0.045, green: 0.095, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.23, blue: 0.59, alpha: 1),
        NSColor(srgbRed: 0.23, green: 0.42, blue: 0.84, alpha: 1)
    ])!.draw(in: tile, angle: 65)
    let edge = NSBezierPath(roundedRect: CGRect(x: 102, y: 102, width: 820, height: 820), xRadius: 180, yRadius: 180)
    NSColor(srgbRed: 0.52, green: 0.71, blue: 1, alpha: 0.45).setStroke()
    edge.lineWidth = 4
    edge.stroke()

    let lens = NSBezierPath(ovalIn: CGRect(x: 266, y: 366, width: 390, height: 390))
    NSColor(srgbRed: 0.38, green: 0.62, blue: 1, alpha: 0.10).setFill()
    lens.fill()
    let handle = NSBezierPath()
    handle.move(to: CGPoint(x: 604, y: 418))
    handle.line(to: CGPoint(x: 748, y: 274))
    handle.lineWidth = 66
    handle.lineCapStyle = .round
    NSColor(srgbRed: 0.88, green: 0.95, blue: 1, alpha: 1).setStroke()
    handle.stroke()
    lens.lineWidth = 55
    lens.stroke()

    let plus = NSBezierPath()
    plus.move(to: CGPoint(x: 387, y: 561))
    plus.line(to: CGPoint(x: 535, y: 561))
    plus.move(to: CGPoint(x: 461, y: 487))
    plus.line(to: CGPoint(x: 461, y: 635))
    plus.lineWidth = 40
    plus.lineCapStyle = .round
    NSColor.white.setStroke()
    plus.stroke()
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if size == 1024 { try data.write(to: root.appendingPathComponent("Resources/AppIcon.png")) }
    }
}
print("Generated 10 icon sizes from vector artwork")
