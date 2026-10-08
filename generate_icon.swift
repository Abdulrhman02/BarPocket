import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let outer = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.58, alpha: 1),
           ending: NSColor(calibratedRed: 0.09, green: 0.53, blue: 0.67, alpha: 1))!.draw(in: outer, angle: -35)
let rim = NSBezierPath(roundedRect: NSRect(x: 195, y: 215, width: 634, height: 590), xRadius: 125, yRadius: 125)
NSColor.white.withAlphaComponent(0.95).setFill()
rim.fill()
let slot = NSBezierPath(roundedRect: NSRect(x: 265, y: 315, width: 494, height: 335), xRadius: 72, yRadius: 72)
NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.61, alpha: 1).setFill()
slot.fill()
for x in [365.0, 512.0, 659.0] {
    let dot = NSBezierPath(ovalIn: NSRect(x: x - 29, y: 452, width: 58, height: 58))
    NSColor.white.setFill()
    dot.fill()
}
let lip = NSBezierPath(roundedRect: NSRect(x: 320, y: 735, width: 384, height: 48), xRadius: 24, yRadius: 24)
NSColor.white.setFill()
lip.fill()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
