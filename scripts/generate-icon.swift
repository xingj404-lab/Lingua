import AppKit

// Original vector artwork. Coordinates use a top-left origin like SVG.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/LinguaMac/Resources")
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
// Two opposing language marks share a central negative space: an original Lingua monogram.
let ink = "#272A2E"
let silver = "#7D838B"
let source = "M 326 290 L 396 290 C 414 290 424 300 424 318 L 424 566 C 424 584 434 594 452 594 L 536 594 L 536 684 L 370 684 C 322 684 298 660 298 612 L 298 318 C 298 300 308 290 326 290 Z"
let target = "M 698 734 L 628 734 C 610 734 600 724 600 706 L 600 458 C 600 440 590 430 572 430 L 488 430 L 488 340 L 654 340 C 702 340 726 364 726 412 L 726 706 C 726 724 716 734 698 734 Z"
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Lingua — languages in balance</title>
<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#E9EBEF"/></linearGradient><filter id="shadow" x="-25%" y="-25%" width="150%" height="160%"><feDropShadow dy="16" stdDeviation="18" flood-opacity="0.10"/></filter></defs>
<rect x="64" y="64" width="896" height="896" rx="196" fill="url(#tile)" stroke="#D6D9DE" stroke-width="2" filter="url(#shadow)"/>
<path d="\(source)" fill="\(ink)"/>
<path d="\(target)" fill="\(silver)"/>
</svg>
"""
try svg.write(to: assets.appendingPathComponent("LinguaLogo.svg"), atomically: true, encoding: .utf8)
func color(_ hex: String) -> NSColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(calibratedRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
}
func path(_ source: String) -> NSBezierPath {
    let tokens = source.split(separator: " ").map(String.init)
    let p = NSBezierPath(); var index = 0
    func point() -> NSPoint {
        let x = Double(tokens[index])!, y = Double(tokens[index + 1])!; index += 2
        return NSPoint(x: x, y: y)
    }
    while index < tokens.count {
        let command = tokens[index]; index += 1
        switch command {
        case "M": p.move(to: point())
        case "L": p.line(to: point())
        case "C": let c1 = point(), c2 = point(), end = point(); p.curve(to: end, controlPoint1: c1, controlPoint2: c2)
        case "Z": p.close()
        default: fatalError("Unsupported path command")
        }
    }
    p.lineCapStyle = .round; p.lineJoinStyle = .round
    return p
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: 1024); transform.scaleX(by: 1, yBy: -1); transform.concat()
let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.10); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
NSColor.white.setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color("#FFFFFF"), ending: color("#E9EBEF"))!.draw(in: tile, angle: 90)
color("#D6D9DE").setStroke(); tile.lineWidth = 2; tile.stroke()
color(ink).setFill(); path(source).fill()
color(silver).setFill(); path(target).fill()
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: resources.appendingPathComponent("AppIcon.png"))
try png.write(to: assets.appendingPathComponent("LinguaLogo.png"))
print("Generated vector logo and 1024px application icon")
