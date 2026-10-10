import AppKit
import ScreenCaptureKit
import Darwin

// Native menu bar window stills only. No display screenshot, SCStream or audio output.
@MainActor
final class IconSnapshots {
    // Native window stills retain transparency and status badges. The window-list
    // API is deprecated, but ScreenCaptureKit does not expose offscreen status items.
    struct StatusWindow { let id: CGWindowID; let pid: pid_t; let frame: CGRect }
    func nativeWindows() -> [StatusWindow] {
        // Resolve optional WindowServer entry points dynamically. A missing
        // symbol fails safely; no dependency on a private framework is linked.
        typealias MainConnection = @convention(c) () -> Int32
        typealias Count = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int32>) -> Int32
        typealias List = @convention(c) (Int32, Int32, Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<Int32>) -> Int32
        guard let handle = dlopen(nil, RTLD_LAZY) else { return [] }
        defer { dlclose(handle) }
        guard let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
              let countSymbol = dlsym(handle, "CGSGetWindowCount"),
              let listSymbol = dlsym(handle, "CGSGetProcessMenuBarWindowList") else { return [] }
        let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
        var count: Int32 = 0
        guard unsafeBitCast(countSymbol, to: Count.self)(connection, 0, &count) == 0, count > 0, count < 100000 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        var actual: Int32 = 0
        guard unsafeBitCast(listSymbol, to: List.self)(connection, 0, count, &ids, &actual) == 0,
              actual > 0, actual <= count else { return [] }
        var pointers = ids.prefix(Int(actual)).map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let numbers = CFArrayCreate(kCFAllocatorDefault, &pointers, Int(actual), nil),
              let windows = CGWindowListCreateDescriptionFromArray(numbers) as? [[String: Any]] else { return [] }
        UserDefaults.standard.set(windows.count, forKey: "nativeStatusWindowCount")
        typealias Frame = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
        guard let frameSymbol = dlsym(handle, "CGSGetScreenRectForWindow") else { return [] }
        let readFrame = unsafeBitCast(frameSymbol, to: Frame.self)
        return windows.compactMap { info -> StatusWindow? in
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return nil }
            var frame = CGRect.zero
            guard readFrame(connection, id, &frame) == 0, frame.width > 0, frame.height > 0 else { return nil }
            return StatusWindow(id: id, pid: pid, frame: frame)
        }
    }

    static func retryDelay(afterFailures: Int) -> TimeInterval? {
        afterFailures < 3 ? 30 : nil
    }

    static func matchedWindow(frame: CGRect, windows: [StatusWindow]) -> StatusWindow? {
        let candidate = windows.filter {
            $0.frame.height <= 60 && $0.frame.width <= 250 &&
            abs($0.frame.midY-frame.midY) < 20 && abs($0.frame.width-frame.width) < 20
        }.min { abs($0.frame.midX-frame.midX) < abs($1.frame.midX-frame.midX) }
        guard let candidate, abs(candidate.frame.midX-frame.midX) < max(4,frame.width/2) else { return nil }
        return candidate
    }

    static func itemIdentity(bundle: String, index: Int, identifier: String?, unique: Bool, windowID: CGWindowID?) -> String {
        if let identifier, !identifier.isEmpty, unique { return "\(bundle):ax:\(identifier)" }
        if let windowID { return "\(bundle):window:\(windowID)" }
        return "\(bundle):\(index)"
    }

    func nativeImage(pid: pid_t, frame: CGRect, windows: [StatusWindow]? = nil) -> NSImage? {
        // macOS can host third-party status windows inside Control Center.
        guard let window = Self.matchedWindow(frame: frame, windows: windows ?? nativeWindows()) else { return nil }
        let id=window.id, bounds=window.frame
        var pointer = UnsafeRawPointer(bitPattern: UInt(id))
        guard let array = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil),
              let image = CGImage(windowListFromArrayScreenBounds: .null, windowArray: array,
                                  imageOption: [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        guard Self.hasArtwork(image) else { return nil }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "nativeStatusCaptureCount") + 1, forKey: "nativeStatusCaptureCount")
        return NSImage(cgImage: image, size: bounds.size)
    }

    /// Remove transparent padding without changing the native point scale.
    /// Preserve Retina pixels, original dimensions and coloured status badges.
    static func normalized(_ image: NSImage) -> NSImage {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let cg = bitmap.cgImage else { return image }
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        var monochrome = true
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.08 {
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    if (channels.max()! - channels.min()!) > 0.1 { monochrome = false }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY,
              let crop = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1)) else { return image }
        let size = NSSize(width: CGFloat(crop.width) * image.size.width / CGFloat(cg.width),
                          height: CGFloat(crop.height) * image.size.height / CGFloat(cg.height))
        let result = NSImage(cgImage: crop, size: size)
        // Native template rendering follows the pocket appearance. A coloured
        // logo or badge remains an original-colour image, with its alpha intact.
        result.isTemplate = monochrome
        if !monochrome && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // A menu bar over light wallpaper may supply black ink even in dark
            // system appearance. Lift only neutral dark ink; keep coloured badges
            // and their light lettering unchanged, along with every alpha pixel.
            guard let context = CGContext(data: nil, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return result }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            for offset in stride(from: 0, to: crop.width * crop.height * 4, by: 4) {
                let alpha = CGFloat(data[offset + 3])
                guard alpha > 20 else { continue }
                let channels = [CGFloat(data[offset])/alpha, CGFloat(data[offset+1])/alpha, CGFloat(data[offset+2])/alpha]
                if channels.max()! < 0.55 && channels.max()! - channels.min()! <= 0.1 {
                    let ink = UInt8((0.95 * alpha).rounded())
                    data[offset] = ink; data[offset+1] = ink; data[offset+2] = ink
                }
            }
            if let adjusted = context.makeImage() {
                let adapted = NSImage(cgImage: adjusted, size: size)
                adapted.isTemplate = false
                return adapted
            }
        }
        return result
    }

    static func hasArtwork(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return false }
        if background.alphaComponent < 0.05 {
            // Disabled native items can be black at ~34% opacity. They are real
            // artwork even though their alpha difference is below the old cutoff.
            var ink = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 { ink += 1 }
                }
            }
            return ink >= 12
        }
        var changed = 0
        for y in (bitmap.pixelsHigh / 6)..<(bitmap.pixelsHigh * 5 / 6) {
            for x in (bitmap.pixelsWide / 5)..<(bitmap.pixelsWide * 4 / 5) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let difference = abs(c.redComponent-background.redComponent) + abs(c.greenComponent-background.greenComponent) + abs(c.blueComponent-background.blueComponent) + abs(c.alphaComponent-background.alphaComponent)
                if difference > 0.45 { changed += 1 }
            }
        }
        return changed >= 12
    }

}
