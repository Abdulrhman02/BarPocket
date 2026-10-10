import AppKit
import ApplicationServices
import Quartz
import ServiceManagement

private struct MenuExtra {
    let element: AXUIElement
    let pid: pid_t
    let name: String
    let title: String
    let id: String
    let frame: CGRect // Accessibility coordinates: origin at the top left of the display.
}

@MainActor
private final class PocketController: NSObject, NSApplicationDelegate {
    private lazy var toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var divider = NSStatusBar.system.statusItem(withLength: 14)
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var manageWindow: NSWindow?
    private var isCollapsed = false
    private var accessibilityReady = false
    private var permissionWindow: NSWindow?
    private var permissionTimer: Timer?
    private var isPanelOpen = false
    private var activatingID: String?
    private var hoverTimer: Timer?
    private var closeTimer: Timer?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var refreshTimer: Timer?
    private var dragPreview: NSPanel?
    private var pocketDragActive = false
    private var suppressPocketClickUntil = Date.distantPast
    private var nativeDragCandidate: MenuExtra?
    private var nativeDragStart: CGPoint?
    private var nativeDragActive = false
    private var openedPanelForNativeDrag = false
    private var extras: [MenuExtra] = []
    private var hiddenCache: [MenuExtra] = []
    private var managedExtras: [MenuExtra] = []
    private var glyphs: [String: NSImage] = [:]
    private var panelButtons: [String: NSButton] = [:]
    private weak var accessLabel: NSTextField?
    private let defaults = UserDefaults.standard
    private let syntheticEventMarker: Int64 = 0x42504F434B4554

    private var hoverEnabled: Bool { defaults.object(forKey: "hoverEnabled") as? Bool ?? true }
    private var autoCloseEnabled: Bool { defaults.object(forKey: "autoCloseEnabled") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // AppKit restores these positions when each named status item is created.
        defaults.set(0.0, forKey: "NSStatusItem Preferred Position BarPocketToggle")
        defaults.set(1.0, forKey: "NSStatusItem Preferred Position BarPocketDivider")
        configureStatusItems()
        loadGlyphCache()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            reconcileAccessibility()
        }
        installMouseMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCache()
                self?.updateAccessLabel()
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcileAccessibility() }
        }
        if !AXIsProcessTrusted() { showPermissionSetup() }
    }

    private func configureStatusItems() {
        toggle.autosaveName = "BarPocketToggle"
        divider.autosaveName = "BarPocketDivider"
        toggle.isVisible = true
        divider.isVisible = true
        toggle.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "BarPocket")
        toggle.button?.image?.isTemplate = true
        toggle.button?.imagePosition = .imageOnly
        toggle.button?.toolTip = "Open pocket. Drag a visible menu bar icon here to hide it."
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleClicked)
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        divider.button?.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Hidden icons start here")
        divider.button?.imagePosition = .imageOnly
        divider.button?.toolTip = nil
        divider.button?.target = self
        divider.button?.action = #selector(dividerClicked)
        divider.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AXIsProcessTrusted() { showSettings() } else { showPermissionSetup() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore the other apps' icons if BarPocket quits.
        divider.length = 14
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        dragPreview?.orderOut(nil)
    }

    @objc private func screenChanged() {
        if isCollapsed { collapse() }
        refreshCache()
        if isPanelOpen { presentPanel() }
    }

    private var collapsedLength: CGFloat {
        let screen = divider.button?.window?.screen ?? NSScreen.main
        let leftEdge = screen?.frame.minX ?? 0
        let measuredRightEdge = divider.button?.window?.frame.maxX ?? 0
        let rightEdge = measuredRightEdge > leftEdge + 300
            ? measuredRightEdge
            : ((screen?.frame.maxX ?? 1500) - 260)
        // Hide the group just beyond the display edge. Pushing it thousands of
        // points away causes macOS to discard some status-window images.
        return min(10_000, max(500, rightEdge - leftEdge + 60))
    }

    private func collapse() {
        guard AXIsProcessTrusted() else { expand(); return }
        divider.length = collapsedLength
        isCollapsed = true
    }

    private func expand() {
        divider.length = 14
        isCollapsed = false
    }

    @objc private func toggleClicked() {
        if nativeDragActive { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: toggle)
        } else if isPanelOpen {
            closePanel()
        } else {
            showPanel()
        }
    }

    @objc private func dividerClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(from: divider) }
        else { toggleNativeBar() }
    }

    private func showContextMenu(from item: NSStatusItem) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let show = NSMenuItem(title: "Show hidden icons", action: #selector(showPanelFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let expandItem = NSMenuItem(title: isCollapsed ? "Expand menu bar temporarily" : "Collapse menu bar", action: #selector(toggleNativeBar), keyEquivalent: "")
        expandItem.target = self
        menu.addItem(expandItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BarPocket", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.performClick(nil)
        DispatchQueue.main.async { item.menu = nil }
    }

    @objc private func showPanelFromMenu() { showPanel() }
    @objc private func toggleNativeBar() {
        guard AXIsProcessTrusted() else { expand(); showPermissionSetup(); return }
        isCollapsed ? expand() : collapse()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == self?.syntheticEventMarker { return }
            Task { @MainActor in
                guard let self else { return }
                switch event.type {
                case .leftMouseDown: self.nativeMouseDown(event)
                case .leftMouseDragged: self.nativeMouseDragged(event)
                case .leftMouseUp: self.nativeMouseUp(event)
                default: self.mouseMoved()
                }
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                if event.type == .leftMouseDragged { self?.nativeMouseDragged(event) }
                else { self?.nativeMouseUp(event) }
            }
            return event
        }
    }

    private func mouseMoved() {
        guard AXIsProcessTrusted() else { return }
        guard let buttonFrame = toggle.button?.window?.frame else { return }
        let point = NSEvent.mouseLocation
        let hoverZone = buttonFrame.insetBy(dx: -10, dy: -9)
        if hoverEnabled && hoverZone.contains(point) && !isPanelOpen {
            if hoverTimer == nil {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.hoverTimer = nil
                        if let frame = self?.toggle.button?.window?.frame,
                           frame.insetBy(dx: -10, dy: -9).contains(NSEvent.mouseLocation) {
                            self?.showPanel()
                        }
                    }
                }
            }
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
        if isPanelOpen && autoCloseEnabled && !nativeDragActive && !pocketDragActive {
            let insidePanel = panel?.frame.insetBy(dx: -8, dy: -8).contains(point) ?? false
            let insideButton = buttonFrame.insetBy(dx: -8, dy: -8).contains(point)
            if insidePanel || insideButton {
                closeTimer?.invalidate(); closeTimer = nil
            } else if closeTimer == nil {
                closeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.closePanel() }
                }
            }
        }
    }

    private func menuBarDropZoneContains(_ point: CGPoint) -> Bool {
        guard let itemFrame = toggle.button?.window?.frame,
              let screen = toggle.button?.window?.screen else { return false }
        let zone = NSRect(x: screen.frame.minX, y: itemFrame.minY - 8,
                          width: screen.frame.width, height: itemFrame.height + 16)
        return zone.contains(point)
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        if let cgPoint = event.cgEvent?.location {
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let cgBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                if cgBounds.contains(cgPoint) {
                    return CGPoint(x: screen.frame.minX + cgPoint.x - cgBounds.minX,
                                   y: screen.frame.maxY - (cgPoint.y - cgBounds.minY))
                }
            }
        }
        if let window = event.window {
            return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return NSEvent.mouseLocation
    }

    private func pocketDragPoint(_ recognizer: NSPanGestureRecognizer) -> CGPoint {
        guard let window = recognizer.view?.window else { return NSEvent.mouseLocation }
        return window.convertToScreen(NSRect(origin: recognizer.location(in: nil), size: .zero)).origin
    }

    private func pocketDropZoneContains(_ point: CGPoint) -> Bool {
        let button = toggle.button?.window?.frame.insetBy(dx: -12, dy: -10)
        let pocket = isPanelOpen ? panel?.frame.insetBy(dx: -6, dy: -6) : nil
        return button?.contains(point) == true || pocket?.contains(point) == true
    }

    private func nativeMouseDown(_ event: NSEvent) {
        guard AXIsProcessTrusted() else { return }
        nativeDragCandidate = nil
        nativeDragStart = nil
        guard menuBarDropZoneContains(screenPoint(for: event)),
              let point = event.cgEvent?.location,
              let boundary = divider.button?.window?.frame.minX else { return }
        nativeDragCandidate = allExtras().first {
            $0.frame.midX > boundary + 2 && $0.frame.insetBy(dx: -2, dy: -2).contains(point)
        }
        if nativeDragCandidate != nil { nativeDragStart = screenPoint(for: event) }
        if let extra = nativeDragCandidate { defaults.set("native down \(extra.name)", forKey: "dragDiagnostics") }
    }

    private func nativeMouseDragged(_ event: NSEvent) {
        guard AXIsProcessTrusted() else { return }
        guard let extra = nativeDragCandidate, let start = nativeDragStart else { return }
        let point = screenPoint(for: event)
        if !nativeDragActive {
            guard hypot(point.x - start.x, point.y - start.y) > 10 else { return }
            nativeDragActive = true
            defaults.set("native drag \(extra.name)", forKey: "dragDiagnostics")
            openedPanelForNativeDrag = !isPanelOpen
            if !isPanelOpen { showPanel() }
            panel?.ignoresMouseEvents = true
            closeTimer?.invalidate(); closeTimer = nil
            beginDragPreview(for: extra)
        }
        moveDragPreview(to: point)
        highlightDropTarget(pocketDropZoneContains(point))
    }

    private func nativeMouseUp(_ event: NSEvent) {
        guard AXIsProcessTrusted() else { return }
        guard let extra = nativeDragCandidate else { return }
        let shouldHide = nativeDragActive && pocketDropZoneContains(screenPoint(for: event))
        defaults.set("native up \(extra.name) accepted=\(shouldHide)", forKey: "dragDiagnostics")
        let closeOpenedPanel = openedPanelForNativeDrag && !shouldHide
        nativeDragCandidate = nil
        nativeDragStart = nil
        nativeDragActive = false
        openedPanelForNativeDrag = false
        panel?.ignoresMouseEvents = false
        endDragPreview()
        highlightDropTarget(false)
        if shouldHide { move(extra: extra, keepVisible: false) }
        else if closeOpenedPanel { closePanel() }
    }

    private func beginDragPreview(for extra: MenuExtra) {
        endDragPreview()
        let frame = NSRect(x: 0, y: 0, width: 34, height: 34)
        let preview = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.level = .popUpMenu
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.hasShadow = true
        preview.ignoresMouseEvents = true
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let tile = NSVisualEffectView(frame: frame)
        tile.material = .popover
        tile.state = .active
        tile.appearance = NSAppearance(named: .darkAqua)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 9
        tile.layer?.masksToBounds = true
        if let glyph = glyphs[extra.id] {
            let image = NSImageView(frame: NSRect(x: 4, y: 4, width: 26, height: 26))
            image.image = displayGlyph(glyph)
            image.contentTintColor = .white
            image.imageScaling = .scaleProportionallyDown
            tile.addSubview(image)
        } else {
            let text = NSTextField(labelWithString: String(extra.title.prefix(2)).uppercased())
            text.frame = NSRect(x: 0, y: 9, width: 34, height: 16)
            text.alignment = .center
            text.textColor = .white
            text.font = .systemFont(ofSize: 10, weight: .semibold)
            tile.addSubview(text)
        }
        preview.contentView = tile
        dragPreview = preview
        moveDragPreview(to: NSEvent.mouseLocation)
        preview.orderFrontRegardless()
    }

    private func moveDragPreview(to point: CGPoint) {
        dragPreview?.setFrameOrigin(NSPoint(x: point.x + 9, y: point.y - 43))
    }

    private func endDragPreview() {
        dragPreview?.orderOut(nil)
        dragPreview = nil
    }

    private func highlightDropTarget(_ active: Bool) {
        toggle.button?.highlight(active)
        if let background = panel?.contentView as? NSVisualEffectView {
            background.layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.16)).cgColor
            background.layer?.borderWidth = active ? 1.5 : 0.5
        }
    }

    private func refreshCache() {
        guard AXIsProcessTrusted() else { return }
        let updated = inventory()
        let oldIDs = hiddenCache.map(\.id)
        hiddenCache = updated
        if isPanelOpen && oldIDs != updated.map(\.id) {
            extras = updated
            presentPanel()
        }
    }

    private func restorePinnedExtras() async {
        guard AXIsProcessTrusted() else { return }
        let pinned = defaults.stringArray(forKey: "pinnedExtras") ?? []
        for id in pinned {
            guard let boundary = divider.button?.window?.frame.minX,
                  let extra = allExtras().first(where: { $0.id == id }),
                  extra.frame.midX < boundary + 2 else { continue }
            if postTargetedCommandDrag(extra: extra, keepVisible: true) {
                try? await Task.sleep(for: .milliseconds(320))
            }
        }
        refreshCache()
    }

    private func loadGlyphCache() {
        let saved = defaults.dictionary(forKey: "statusGlyphCache") as? [String: Data] ?? [:]
        glyphs = saved.compactMapValues { NSImage(data: $0) }
    }

    private func displayGlyph(_ original: NSImage) -> NSImage {
        guard let copy = original.copy() as? NSImage,
              let data = original.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return original }
        var visible = 0
        var colored = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.15 else { continue }
                visible += 1
                let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
                let minimum = min(color.redComponent, color.greenComponent, color.blueComponent)
                if maximum > 0.15 && (maximum - minimum) / maximum > 0.18 { colored += 1 }
            }
        }
        if visible > 0 && Double(colored) / Double(visible) < 0.03 { copy.isTemplate = true }
        return copy
    }

    private func showPanel() {
        guard activatingID == nil else { return }
        guard AXIsProcessTrusted() else {
            expand()
            showPermissionSetup()
            return
        }
        closeTimer?.invalidate(); closeTimer = nil
        extras = hiddenCache
        presentPanel()
        if extras.isEmpty { refreshCache() }
    }

    private func presentPanel() {
        let content = makePanelContent()
        let idealWidth = CGFloat(max(extras.count, 1)) * 27 + 16
        let width = min(max(idealWidth, 76), (NSScreen.main?.frame.width ?? 900) - 20)
        let height: CGFloat = 40
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        panel?.contentView = content
        let screen = toggle.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let anchor = toggle.button?.window?.frame ?? NSRect(x: screenFrame.maxX - 100, y: screenFrame.maxY - 30, width: 30, height: 25)
        let x = min(max(anchor.maxX - width, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        let y = anchor.minY - height - 3
        panel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel?.orderFrontRegardless()
        isPanelOpen = true
    }

    private func closePanel() {
        closeTimer?.invalidate(); closeTimer = nil
        panel?.orderOut(nil)
        isPanelOpen = false
    }

    private func makePanelContent() -> NSView {
        panelButtons.removeAll()
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.wantsLayer = true
        background.layer?.cornerRadius = 11
        background.layer?.masksToBounds = true
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        background.layer?.borderWidth = 0.5

        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 1
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        if extras.isEmpty {
            let label = NSTextField(labelWithString: "No hidden icons found.")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            row.addArrangedSubview(label)
        } else {
            for (index, extra) in extras.enumerated() {
                let button = NSButton()
                button.bezelStyle = .recessed
                button.isBordered = false
                button.image = glyphs[extra.id].map(displayGlyph)
                button.imagePosition = button.image == nil ? .noImage : .imageOnly
                button.contentTintColor = .white
                if button.image == nil {
                    button.attributedTitle = NSAttributedString(
                        string: String(extra.title.prefix(2)).uppercased(),
                        attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10, weight: .semibold)]
                    )
                    button.contentTintColor = NSColor.white
                }
                button.imageScaling = .scaleProportionallyDown
                button.toolTip = "\(extra.name): \(extra.title) — click to open"
                button.tag = index
                panelButtons[extra.id] = button
                button.target = self
                button.action = #selector(extraClicked(_:))
                button.translatesAutoresizingMaskIntoConstraints = false
                button.widthAnchor.constraint(equalToConstant: 26).isActive = true
                button.heightAnchor.constraint(equalToConstant: 26).isActive = true
                let recognizer = NSClickGestureRecognizer(target: self, action: #selector(extraRightClicked(_:)))
                recognizer.buttonMask = 0x2
                button.addGestureRecognizer(recognizer)
                let drag = NSPanGestureRecognizer(target: self, action: #selector(extraDragged(_:)))
                button.addGestureRecognizer(drag)
                row.addArrangedSubview(button)
            }
        }
        scroll.documentView = row
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -2),
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -4),
            row.heightAnchor.constraint(equalToConstant: 32),
            row.widthAnchor.constraint(greaterThanOrEqualTo: scroll.widthAnchor)
        ])
        return background
    }

    @objc private func extraClicked(_ sender: NSButton) {
        guard extras.indices.contains(sender.tag), activatingID == nil,
              Date() >= suppressPocketClickUntil else { return }
        let extra = extras[sender.tag]
        activatingID = extra.id
        closePanel()
        Task { @MainActor in
            defer { if activatingID == extra.id { activatingID = nil } }
            let beforeWindows = interfaceWindowIDs(pid: extra.pid)
            let beforePopups = Set(menuPopupWindows().keys)
            guard let initial = allExtras().first(where: { $0.id == extra.id }),
                  postTargetedCommandDrag(extra: initial, keepVisible: true) else {
                NSSound.beep(); return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard let visible = allExtras().first(where: { $0.id == extra.id }),
                  let boundary = divider.button?.window?.frame.minX,
                  visible.frame.midX > boundary + 2 else {
                defaults.set("move-failed", forKey: "activationDiagnostics")
                NSSound.beep(); return
            }
            let openedDuringMove = interfaceWindowIDs(pid: extra.pid).subtracting(beforeWindows)
            var popups = popupIDs(near: visible.frame.midX).subtracting(beforePopups)
            var clicked = false
            var axResult: AXError = .failure
            if openedDuringMove.isEmpty && popups.isEmpty {
                clicked = clickVisibleExtra(visible)
                for _ in 0..<12 where popups.isEmpty {
                    try? await Task.sleep(for: .milliseconds(100))
                    popups = popupIDs(near: visible.frame.midX).subtracting(beforePopups)
                    if !interfaceWindowIDs(pid: extra.pid).subtracting(beforeWindows).isEmpty { break }
                }
            }
            if popups.isEmpty && interfaceWindowIDs(pid: extra.pid).subtracting(beforeWindows).isEmpty {
                guard AXIsProcessTrusted() else { return }
                axResult = AXUIElementPerformAction(visible.element, kAXPressAction as CFString)
                for _ in 0..<10 where popups.isEmpty {
                    try? await Task.sleep(for: .milliseconds(100))
                    popups = popupIDs(near: visible.frame.midX).subtracting(beforePopups)
                    if !interfaceWindowIDs(pid: extra.pid).subtracting(beforeWindows).isEmpty { break }
                }
            }
            let opened = interfaceWindowIDs(pid: extra.pid).subtracting(beforeWindows)
            defaults.set("clicked=\(clicked) ax=\(axResult.rawValue) visibleX=\(Int(visible.frame.midX)) windows=\(opened.count) popups=\(popups.count)", forKey: "activationDiagnostics")
            if !popups.isEmpty || !opened.isEmpty {
                activatingID = nil
                var quietChecks = 0
                while quietChecks < 5 {
                    try? await Task.sleep(for: .milliseconds(150))
                    let currentPopups = popupIDs(near: visible.frame.midX).subtracting(beforePopups)
                    let currentWindows = interfaceWindowIDs(pid: extra.pid).intersection(opened)
                    quietChecks = currentPopups.isEmpty && currentWindows.isEmpty ? quietChecks + 1 : 0
                }
            } else {
                // If activation did not expose a menu, leave its real icon reachable
                // so the user can click it directly instead of bouncing it back.
                NSSound.beep()
                refreshCache()
                return
            }
            if let current = allExtras().first(where: { $0.id == extra.id }) {
                _ = postTargetedCommandDrag(extra: current, keepVisible: false)
                try? await Task.sleep(for: .milliseconds(240))
            }
            refreshCache()
        }
    }

    private func menuPopupWindows() -> [Int: CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [Int: CGRect] = [:]
        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0 && layer < 1000 && layer != Int(kCGStatusWindowLevel),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 60, frame.height > 40, frame.minY < 150 else { continue }
            result[id] = frame
        }
        return result
    }

    private func popupIDs(near x: CGFloat) -> Set<Int> {
        Set(menuPopupWindows().compactMap { id, frame in
            frame.minX - 80 <= x && x <= frame.maxX + 80 ? id : nil
        })
    }

    private func interfaceWindowIDs(pid: pid_t) -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { info in
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer != Int(kCGStatusWindowLevel),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 60, frame.height > 40 else { return nil }
            return id
        })
    }

    private func clickVisibleExtra(_ extra: MenuExtra) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidate = windows.compactMap { info -> CGRect? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == Int(kCGStatusWindowLevel),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  abs(frame.midX - extra.frame.midX) < 12,
                  abs(frame.width - extra.frame.width) < 20 else { return nil }
            return frame
        }.min(by: { abs($0.midX - extra.frame.midX) < abs($1.midX - extra.frame.midX) })
        guard let frame = candidate, frame.midX > 0 else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        func event(_ type: CGEventType) -> CGEvent? {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            return event
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return false }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
        up.post(tap: .cghidEventTap)
        return true
    }

    @objc private func extraRightClicked(_ recognizer: NSClickGestureRecognizer) {
        guard let button = recognizer.view as? NSButton, extras.indices.contains(button.tag) else { return }
        let menu = NSMenu()
        let pin = NSMenuItem(title: "Keep visible in menu bar", action: #selector(pinClicked(_:)), keyEquivalent: "")
        pin.target = self
        pin.tag = button.tag
        menu.addItem(pin)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    @objc private func extraDragged(_ recognizer: NSPanGestureRecognizer) {
        guard let button = recognizer.view as? NSButton,
              extras.indices.contains(button.tag) else { return }
        let extra = extras[button.tag]
        switch recognizer.state {
        case .began:
            pocketDragActive = true
            defaults.set("pocket drag \(extra.name)", forKey: "dragDiagnostics")
            suppressPocketClickUntil = Date().addingTimeInterval(1)
            closeTimer?.invalidate(); closeTimer = nil
            beginDragPreview(for: extra)
        case .changed:
            let point = pocketDragPoint(recognizer)
            moveDragPreview(to: point)
            highlightDropTarget(menuBarDropZoneContains(point))
        case .ended:
            let point = pocketDragPoint(recognizer)
            let shouldPin = menuBarDropZoneContains(point)
            defaults.set("pocket up \(extra.name) accepted=\(shouldPin) point=\(point) bar=\(toggle.button?.window?.frame ?? .zero) panel=\(panel?.frame ?? .zero)", forKey: "dragDiagnostics")
            pocketDragActive = false
            suppressPocketClickUntil = Date().addingTimeInterval(0.5)
            endDragPreview()
            highlightDropTarget(false)
            if shouldPin {
                closePanel()
                move(extra: extra, keepVisible: true)
            }
        case .cancelled, .failed:
            pocketDragActive = false
            suppressPocketClickUntil = Date().addingTimeInterval(0.5)
            endDragPreview()
            highlightDropTarget(false)
        default:
            break
        }
    }

    @objc private func pinClicked(_ sender: NSMenuItem) {
        guard extras.indices.contains(sender.tag) else { return }
        let extra = extras[sender.tag]
        closePanel()
        move(extra: extra, keepVisible: true)
    }

    private func move(extra: MenuExtra, keepVisible: Bool) {
        Task { @MainActor in
            guard let current = allExtras().first(where: { $0.id == extra.id }) else { return }
            let posted = postTargetedCommandDrag(extra: current, keepVisible: keepVisible)
            try? await Task.sleep(for: .milliseconds(320))
            let boundary = divider.button?.window?.frame.minX ?? 0
            let actual = allExtras().first(where: { $0.id == extra.id })?.frame.midX
            defaults.set("posted=\(posted) expectedVisible=\(keepVisible) actualX=\(actual.map { Int($0) } ?? -1) boundary=\(Int(boundary))", forKey: "moveDiagnostics")
            if posted, let actual, (actual > boundary + 2) == keepVisible {
                var pinned = Set(defaults.stringArray(forKey: "pinnedExtras") ?? [])
                if keepVisible { pinned.insert(extra.id) }
                else { pinned.remove(extra.id) }
                defaults.set(pinned.sorted(), forKey: "pinnedExtras")
            }
            refreshCache()
            if manageWindow?.isVisible == true { showManageWindow() }
        }
    }

    private func postTargetedCommandDrag(extra: MenuExtra, keepVisible: Bool) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let dividerFrame = divider.button?.window?.frame else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let records: [(id: Int, pid: pid_t, layer: Int, frame: CGRect)] = windows.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (id, pid, layer, frame)
        }
        let wideStatusWindows = records.filter { $0.layer == Int(kCGStatusWindowLevel) && $0.frame.width > 200 }
        guard let target = wideStatusWindows.min(by: {
                  abs($0.frame.minX - dividerFrame.minX) + abs($0.frame.width - dividerFrame.width)
                    < abs($1.frame.minX - dividerFrame.minX) + abs($1.frame.width - dividerFrame.width)
              }),
              let item = records.filter({ $0.layer == Int(kCGStatusWindowLevel) && abs($0.frame.midX - extra.frame.midX) < 12 && abs($0.frame.width - extra.frame.width) < 20 })
                .min(by: { abs($0.frame.midX - extra.frame.midX) < abs($1.frame.midX - extra.frame.midX) }),
              let display = NSScreen.main,
              let source = CGEventSource(stateID: NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier == "com.apple.controlcenter" ? .hidSystemState : .privateState) else { return false }
        let left = display.frame.minX + 8
        let right = display.frame.maxX - 8
        let startX = (left...right).contains(item.frame.midX)
            ? item.frame.midX
            : min(max(target.frame.midX, left), right)
        let endX = keepVisible
            ? min(max(target.frame.maxX + 6, left), right)
            : min(max(target.frame.minX + target.frame.width * 0.25, left), right)
        let start = CGPoint(x: startX, y: min(max(item.frame.midY, 8), 40))
        let end = CGPoint(x: endX, y: min(max(target.frame.midY, 8), 40))
        let protected = NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier == "com.apple.controlcenter"
        func event(_ type: CGEventType, _ point: CGPoint, _ windowID: Int) -> CGEvent? {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
            event.flags = [.maskCommand]
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            if !protected { event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.pid)) }
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            if let field = CGEventField(rawValue: 0x33) { event.setIntegerValueField(field, value: Int64(windowID)) }
            return event
        }
        guard let down = event(.leftMouseDown, start, item.id),
              let dragged = event(.leftMouseDragged, end, target.id),
              let up = event(.leftMouseUp, end, target.id) else { return false }
        let pointer = CGEvent(source: nil)?.location
        let tap: CGEventTapLocation = protected ? .cghidEventTap : .cgSessionEventTap
        down.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.08)
        dragged.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.08)
        up.post(tap: tap)
        if let pointer, let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pointer, mouseButton: .left) {
            restore.post(tap: .cghidEventTap)
        }
        return true
    }

    private func inventory() -> [MenuExtra] {
        guard let dividerFrame = divider.button?.window?.frame else { return [] }
        let boundary = dividerFrame.minX
        return allExtras().filter { $0.frame.midX < boundary + 2 }
    }

    private func allExtras() -> [MenuExtra] {
        guard AXIsProcessTrusted() else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [MenuExtra] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != myPID {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.2)
            var barRef: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &barRef) == .success,
                  let bar = barRef else { continue }
            var childrenRef: AnyObject?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { continue }
            for (index, child) in children.enumerated() {
                var positionRef: AnyObject?
                var sizeRef: AnyObject?
                guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &positionRef) == .success,
                      AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef) == .success,
                      let positionRef, let sizeRef else { continue }
                var origin = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
                      AXValueGetValue(sizeRef as! AXValue, .cgSize, &size), size.width > 0 else { continue }
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef)
                let name = app.localizedName ?? "Menu bar item"
                let title = (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
                let identity = app.bundleIdentifier ?? name
                result.append(MenuExtra(element: child, pid: app.processIdentifier, name: name, title: title, id: "\(identity):\(index)", frame: CGRect(origin: origin, size: size)))
            }
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    // Keep permission changes separate from inventory refreshes: denying or
    // revoking access must never leave native icons hidden behind our divider.
    private func reconcileAccessibility() {
        let trusted = AXIsProcessTrusted()
        updateAccessLabel()
        guard trusted != accessibilityReady else {
            if !trusted { expand() }
            return
        }
        accessibilityReady = trusted
        if trusted {
            permissionWindow?.orderOut(nil)
            collapse()
            refreshCache()
            Task { @MainActor in await restorePinnedExtras() }
            toggle.button?.toolTip = "Open pocket. Drag a visible menu bar icon here to hide it."
        } else {
            expand()
            closePanel()
            manageWindow?.orderOut(nil)
            hoverTimer?.invalidate(); hoverTimer = nil
            nativeDragCandidate = nil; nativeDragStart = nil
            nativeDragActive = false; pocketDragActive = false
            endDragPreview()
            hiddenCache = []; extras = []
            showPermissionSetup()
        }
    }

    private func showPermissionSetup() {
        expand()
        toggle.button?.toolTip = "Set up Accessibility to use BarPocket. Your icons stay visible until access is enabled."
        if permissionWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Set up BarPocket"
            window.isReleasedWhenClosed = false
            let heading = NSTextField(labelWithString: "Allow Accessibility to use BarPocket")
            heading.font = .systemFont(ofSize: 17, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: "BarPocket needs permission to find, open, and move your menu bar icons. Until you enable it, your icons stay visible and the pocket stays inactive.")
            let steps = NSTextField(wrappingLabelWithString: "1. Open Accessibility settings below.\n2. Turn on BarPocket in the list.\nIf it is missing, click + and select this app. Use Show BarPocket in Finder below to locate the right copy.\n\nBarPocket starts automatically once access is enabled. It does not record your screen.")
            steps.textColor = .secondaryLabelColor
            let button = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibilitySettings))
            button.bezelStyle = .rounded
            let locate = NSButton(title: "Show BarPocket in Finder", target: self, action: #selector(revealRunningApp))
            locate.bezelStyle = .rounded
            let stack = NSStackView(views: [heading, detail, steps, button, locate])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
            ])
            permissionWindow = window
        }
        permissionWindow?.center()
        permissionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateAccessLabel() {
        accessLabel?.stringValue = AXIsProcessTrusted() ? "Access enabled" : "Access required"
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 530), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "BarPocket"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        let root = NSVisualEffectView(frame: window.contentView!.bounds)
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root
        func text(_ value: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            return field
        }
        func card(_ title: String, _ children: [NSView]) -> NSBox {
            let box = NSBox()
            box.boxType = .custom
            box.borderColor = .separatorColor
            box.borderWidth = 0
            box.cornerRadius = 10
            box.fillColor = .controlBackgroundColor
            box.contentViewMargins = NSSize(width: 16, height: 14)
            let column = NSStackView(views: [text(title, size: 13, weight: .semibold)] + children)
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 12
            column.translatesAutoresizingMaskIntoConstraints = false
            box.contentView!.addSubview(column)
            NSLayoutConstraint.activate([
                column.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
                column.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
                column.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
                column.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
            ])
            return box
        }
        func switchRow(_ title: String, _ detail: String, _ enabled: Bool, _ selector: Selector) -> NSView {
            let control = NSSwitch(); control.target = self; control.action = selector; control.state = enabled ? .on : .off
            control.setAccessibilityLabel(title)
            let labels = NSStackView(views: [text(title, size: 13, weight: .medium), text(detail, size: 11, secondary: true)])
            labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 4
            let row = NSStackView(views: [labels, NSView(), control]); row.spacing = 16
            row.widthAnchor.constraint(equalToConstant: 432).isActive = true
            return row
        }
        let behavior = card("GENERAL", [
            switchRow("Open on hover", "Show the pocket when the pointer rests on its icon.", hoverEnabled, #selector(hoverChanged(_:))),
            switchRow("Close automatically", "Dismiss the pocket when you move away.", autoCloseEnabled, #selector(autoCloseChanged(_:))),
            switchRow("Launch at login", "Keep BarPocket ready when your Mac starts.", SMAppService.mainApp.status == .enabled, #selector(launchChanged(_:)))
        ])
        let manage = NSButton(title: "Manage icons…", target: self, action: #selector(showManageWindow))
        let show = NSButton(title: "Open pocket", target: self, action: #selector(showPanelFromMenu))
        let arrange = NSButton(title: "Expand menu bar", target: self, action: #selector(toggleNativeBar))
        let actions = NSStackView(views: [manage, show, arrange]); actions.spacing = 8
        let items = card("YOUR MENU BAR", [text("Choose what stays visible and what goes in the pocket.", secondary: true), actions])
        let access = text(AXIsProcessTrusted() ? "Access enabled" : "Access required", size: 12, weight: .medium)
        accessLabel = access
        let accessButton = NSButton(title: "Open System Settings…", target: self, action: #selector(openAccessibilitySettings))
        let permissions = card("ACCESSIBILITY", [access, text("Allow BarPocket to move and open menu bar items.", size: 11, secondary: true), accessButton])
        let privacy = text("Works locally on your Mac. No account needed.", size: 11, secondary: true)
        let stack = NSStackView(views: [behavior, items, permissions, privacy])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)
        ])
        for box in [behavior, items, permissions] { box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        privacy.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return window
    }

    @objc private func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func showManageWindow() {
        guard AXIsProcessTrusted() else { showPermissionSetup(); return }
        managedExtras = allExtras()
        let window: NSWindow
        if let existing = manageWindow { window = existing }
        else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Manage Menu Bar Icons"
            window.isReleasedWhenClosed = false
            manageWindow = window
        }
        let scroll = NSScrollView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 470, height: 430))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 9
        list.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let heading = NSTextField(labelWithString: "Move an icon between the pocket and menu bar")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        list.addArrangedSubview(heading)
        let boundary = divider.button?.window?.frame.minX ?? 0
        for (index, extra) in managedExtras.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            if let glyph = glyphs[extra.id] {
                let image = NSImageView(image: glyph)
                image.imageScaling = .scaleProportionallyDown
                image.translatesAutoresizingMaskIntoConstraints = false
                image.widthAnchor.constraint(equalToConstant: 22).isActive = true
                image.heightAnchor.constraint(equalToConstant: 22).isActive = true
                row.addArrangedSubview(image)
            }
            let label = NSTextField(labelWithString: extra.title)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = extra.name
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 230).isActive = true
            row.addArrangedSubview(label)
            let hidden = extra.frame.midX < boundary + 2
            let button = NSButton(title: hidden ? "Keep visible" : "Move to pocket", target: self, action: #selector(manageMoveClicked(_:)))
            button.tag = index
            row.addArrangedSubview(button)
            list.addArrangedSubview(row)
        }
        if managedExtras.isEmpty {
            list.addArrangedSubview(NSTextField(labelWithString: "No menu bar icons found. Check Accessibility access."))
        }
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: max(430, CGFloat(managedExtras.count) * 36 + 70)))
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor)
        ])
        scroll.documentView = document
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func manageMoveClicked(_ sender: NSButton) {
        guard managedExtras.indices.contains(sender.tag) else { return }
        let extra = managedExtras[sender.tag]
        let boundary = divider.button?.window?.frame.minX ?? 0
        move(extra: extra, keepVisible: extra.frame.midX < boundary + 2)
    }
    @objc private func hoverChanged(_ sender: NSSwitch) { defaults.set(sender.state == .on, forKey: "hoverEnabled") }
    @objc private func autoCloseChanged(_ sender: NSSwitch) { defaults.set(sender.state == .on, forKey: "autoCloseEnabled") }
    @objc private func launchChanged(_ sender: NSSwitch) {
        if sender.state == .on { try? SMAppService.mainApp.register() }
        else { try? SMAppService.mainApp.unregister() }
    }
}

@MainActor
@discardableResult
private func activateExistingInstance(legacyOnly: Bool = false) -> Bool {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    guard let existing = NSWorkspace.shared.runningApplications.first(where: { running in
        guard running.processIdentifier != currentPID,
              !running.isTerminated,
              running.bundleIdentifier?.hasPrefix("com.abdul.barpocket") == true ||
              running.executableURL?.lastPathComponent == "BarPocket" else { return false }
        if legacyOnly, let url = running.bundleURL,
           let build = Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String,
           let number = Int(build), number >= 7 {
            // New builds arbitrate through the lock, including simultaneous launches.
            return false
        }
        return true
    }) else { return false }
    existing.activate(options: [.activateIgnoringOtherApps])
    return true
}

@MainActor
private func startApp() {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BarPocket", isDirectory: true)
    let instanceLock: SingleInstanceLock
    do {
        guard let acquired = try SingleInstanceLock.acquire(at: directory) else {
            activateExistingInstance()
            return
        }
        instanceLock = acquired
    } catch {
        NSLog("BarPocket cannot acquire its single-instance lock: %@", String(describing: error))
        return
    }
    // Older builds do not hold a lock. Do not add another status item beside one.
    if activateExistingInstance(legacyOnly: true) { return }
    let app = NSApplication.shared
    let controller = PocketController()
    app.delegate = controller
    withExtendedLifetime(instanceLock) { app.run() }
}

MainActor.assumeIsolated { startApp() }
