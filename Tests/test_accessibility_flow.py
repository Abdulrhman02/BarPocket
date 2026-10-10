"""Exercise the production controller with simulated trust, without granting OS access.
Inventory restoration is disabled in the harness to avoid moving real menu items.
"""
from pathlib import Path
import subprocess
import platform
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'main.swift').read_text()
source = source.replace('AXIsProcessTrusted()', 'testTrusted')
source = source.replace('CGPreflightScreenCaptureAccess()', 'testCaptureTrusted')
source = source.replace('    private func refreshCache() {', '    private func refreshCache() { return;')
source = source.replace('    private func restorePinnedExtras() async {', '    private func restorePinnedExtras() async { return;')
source = source.replace('await captureIcons()', 'testCaptureRequests += 1')
source = source[:source.index('MainActor.assumeIsolated { startApp() }')]
source += '''
private var testTrusted = false
private var testCaptureTrusted = false
private var testCaptureRequests = 0
extension PocketController {
    func verifyPermissionFlow() {
        configureStatusItems()
        defer {
            NSStatusBar.system.removeStatusItem(toggle)
            NSStatusBar.system.removeStatusItem(divider)
            permissionWindow?.close()
        }
        assert(!isCollapsed)
        showCaptureSetup()
        captureWindow!.contentView!.layoutSubtreeIfNeeded()
        let setupStack = captureWindow!.contentView!.subviews.first as! NSStackView
        assert(setupStack.frame.minY >= 0 && setupStack.frame.maxY <= captureWindow!.contentView!.bounds.height, "Permission text and button must fit")
        captureWindow?.close()
        collapse()
        assert(!isCollapsed && divider.length == 14)
        showPanel()
        assert(!isPanelOpen && permissionWindow?.isVisible == true)
        assert(settingsWindow == nil)
        testTrusted = true
        reconcileAccessibility()
        assert(accessibilityReady && !isCollapsed)
        testCaptureTrusted = true
        reconcileAccessibility()
        assert(screenCaptureReady, "Capture regrant must be reconciled while AX stays enabled")
        captureReady = true
        collapse()
        assert(accessibilityReady && isCollapsed && divider.length > 14)
        assert(permissionWindow?.isVisible == false)
        captureFailures.insert("unavailable")
        collapse()
        assert(!isCollapsed && divider.length == 14)
        captureFailures.removeAll()
        testCaptureTrusted = false
        collapse()
        assert(!isCollapsed, "Collapse must check current capture permission directly")
        reconcileAccessibility()
        assert(!screenCaptureReady)
        assert(!isCollapsed && divider.length == 14)
        testTrusted = false
        reconcileAccessibility()
        assert(!accessibilityReady && !isCollapsed && divider.length == 14)
        assert(!isPanelOpen && permissionWindow?.isVisible == true)
        collapse()
        assert(!isCollapsed && divider.length == 14)
        print("PASS: Accessibility alone cannot hide; capture/failure gate holds; permission revocation restores visibility.")
    }
}
MainActor.assumeIsolated {
    _ = NSApplication.shared
    PocketController().verifyPermissionFlow()
}
'''
with tempfile.TemporaryDirectory(prefix='barpocket-access-test-') as folder:
    path=Path(folder)
    (path/'main.swift').write_text(source)
    subprocess.run(['xcrun','swiftc','-target',f'{platform.machine()}-apple-macosx14.0','-swift-version','5','-framework','ScreenCaptureKit','-framework','AppKit','-framework','ApplicationServices','-framework','ServiceManagement',str(path/'main.swift'),str(root/'SingleInstance.swift'),str(root/'IconSnapshots.swift'),'-o',str(path/'test')],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    subprocess.run([str(path/'test')],check=True)
