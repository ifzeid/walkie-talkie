import AppKit
import Foundation

let root = CommandLine.arguments[1]
let directory = URL(fileURLWithPath: root).appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.24); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    color(0.08, 0.36, 0.86).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.08, 0.37, 0.88), ending: color(0.27, 0.72, 1))!.draw(in: shape, angle: 85)
    color(1, 1, 1, 0.36).setStroke(); shape.lineWidth = 2; shape.stroke()
    // Two sculpted speech bubbles form a compact two-way radio conversation.
    func bubble(_ rect: NSRect, leftTail: Bool, fill: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 66, yRadius: 66)
        let tail = NSBezierPath()
        if leftTail { tail.move(to: NSPoint(x: rect.minX + 55, y: rect.minY + 30)); tail.line(to: NSPoint(x: rect.minX + 48, y: rect.minY - 55)); tail.line(to: NSPoint(x: rect.minX + 146, y: rect.minY + 12)) }
        else { tail.move(to: NSPoint(x: rect.maxX - 55, y: rect.minY + 30)); tail.line(to: NSPoint(x: rect.maxX - 48, y: rect.minY - 55)); tail.line(to: NSPoint(x: rect.maxX - 146, y: rect.minY + 12)) }
        tail.close(); path.append(leftTail ? tail : tail.reversed)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = color(0, 0.13, 0.42, 0.2); shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
        fill.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
    }
    bubble(NSRect(x: 407, y: 290, width: 366, height: 288), leftTail: false, fill: color(0.70, 0.91, 1))
    bubble(NSRect(x: 243, y: 452, width: 389, height: 291), leftTail: true, fill: color(0.98, 0.995, 1))
    func arrow(x: CGFloat, y: CGFloat, right: Bool, ink: NSColor) {
        let p = NSBezierPath(); p.lineWidth = 25; p.lineCapStyle = .round; p.lineJoinStyle = .round
        let direction: CGFloat = right ? 1 : -1
        p.move(to: NSPoint(x: x - direction * 70, y: y)); p.line(to: NSPoint(x: x + direction * 70, y: y))
        p.move(to: NSPoint(x: x + direction * 29, y: y + 42)); p.line(to: NSPoint(x: x + direction * 72, y: y)); p.line(to: NSPoint(x: x + direction * 29, y: y - 42)); ink.setStroke(); p.stroke()
    }
    arrow(x: 438, y: 597, right: true, ink: color(0.10, 0.48, 0.90))
    arrow(x: 593, y: 388, right: false, ink: color(0.10, 0.44, 0.81))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = drawIcon(size: points * scale)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
print("Generated macOS icon set")
