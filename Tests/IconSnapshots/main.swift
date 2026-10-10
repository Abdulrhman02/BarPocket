import AppKit
@MainActor func checkArtwork() {
    let space=CGColorSpaceCreateDeviceRGB()
    let ctx=CGContext(data:nil,width:48,height:48,bitsPerComponent:8,bytesPerRow:192,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray:0.1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:48,height:48))
    assert(!IconSnapshots.hasArtwork(ctx.makeImage()!))
    ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:16,y:16,width:16,height:16))
    assert(IconSnapshots.hasArtwork(ctx.makeImage()!))
    ctx.clear(CGRect(x:0,y:0,width:48,height:48))
    ctx.setFillColor(CGColor(gray:0,alpha:1));ctx.fill(CGRect(x:16,y:16,width:16,height:16))
    assert(IconSnapshots.hasArtwork(ctx.makeImage()!), "Black artwork on transparency is not blank")
    let normal = IconSnapshots.normalized(NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:24,height:24)))
    assert(normal.size.height == 8 && normal.size.width == 8)
    assert(normal.isTemplate, "Monochrome artwork should adapt to light/dark native tint")
    ctx.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));ctx.fill(CGRect(x:30,y:14,width:5,height:5))
    let badge = IconSnapshots.normalized(NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:24,height:24)))
    let bitmap = NSBitmapImageRep(data: badge.tiffRepresentation!)!
    var red = false
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
        let c=bitmap.colorAt(x:x,y:y)!
        if c.redComponent > 0.8 && c.greenComponent < 0.2 && c.alphaComponent > 0.8 { red=true }
    }}
    assert(red, "Colour badges must survive normalization")
    assert(!badge.isTemplate, "Colour badges must not be template-tinted")
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let darkBadge = IconSnapshots.normalized(NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:24,height:24)))
    let darkPixels = NSBitmapImageRep(data:darkBadge.tiffRepresentation!)!
    assert(!darkBadge.isTemplate)
    assert((darkPixels.colorAt(x:5,y:5)?.redComponent ?? 0) > 0.8, "Neutral logo ink must remain visible on dark material")
    var retainedRed = false
    for y in 0..<darkPixels.pixelsHigh { for x in 0..<darkPixels.pixelsWide {
        let c=darkPixels.colorAt(x:x,y:y)!
        if c.redComponent > 0.8 && c.greenComponent < 0.2 && c.alphaComponent > 0.8 { retainedRed=true }
    }}
    assert(retainedRed, "Dark adaptation must preserve the badge colour")
    NSApp.appearance = nil
    ctx.clear(CGRect(x:0,y:0,width:48,height:48))
    ctx.setFillColor(CGColor(gray:0,alpha:0.34));ctx.fill(CGRect(x:16,y:16,width:16,height:16))
    assert(IconSnapshots.hasArtwork(ctx.makeImage()!), "Disabled black artwork at native opacity is not blank")
    print("PASS: blank rejection, transparent black artwork, native point size and coloured badges.")
}
MainActor.assumeIsolated { _ = NSApplication.shared; checkArtwork() }

MainActor.assumeIsolated {
assert(IconSnapshots.retryDelay(afterFailures: 1) == 30)
assert(IconSnapshots.retryDelay(afterFailures: 2) == 30)
assert(IconSnapshots.retryDelay(afterFailures: 3) == nil, "Background capture retries must stop")
let before = IconSnapshots.itemIdentity(bundle: "test", index: 0, identifier: "battery", unique: true, windowID: 10)
let reordered = IconSnapshots.itemIdentity(bundle: "test", index: 3, identifier: "battery", unique: true, windowID: 11)
assert(before == reordered)
assert(before != IconSnapshots.itemIdentity(bundle: "test", index: 0, identifier: "wifi", unique: true, windowID: 12))
let fallback = IconSnapshots.itemIdentity(bundle: "test", index: 0, identifier: nil, unique: false, windowID: 22)
assert(fallback == IconSnapshots.itemIdentity(bundle: "test", index: 2, identifier: nil, unique: false, windowID: 22))
assert(fallback != IconSnapshots.itemIdentity(bundle: "test", index: 0, identifier: nil, unique: false, windowID: 23))
assert(IconSnapshots.itemIdentity(bundle: "test", index: 1, identifier: "duplicate", unique: false, windowID: 23) == "test:window:23")
print("PASS: stable AX identity across reorder; unique window fallback; duplicate AX identifiers cannot collide.")

}
