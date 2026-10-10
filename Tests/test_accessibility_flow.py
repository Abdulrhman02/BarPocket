"""Exercise the production controller with simulated trust, without granting OS access.
Inventory restoration is disabled in the harness to avoid moving real menu items.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'main.swift').read_text()
source = source.replace('AXIsProcessTrusted()', 'testTrusted')
source = source.replace('    private func refreshCache() {', '    private func refreshCache() { return;')
source = source.replace('    private func restorePinnedExtras() async {', '    private func restorePinnedExtras() async { return;')
source = source[:source.index('MainActor.assumeIsolated { startApp() }')]
source += '''
private var testTrusted = false
extension PocketController {
    func verifyPermissionFlow() {
        configureStatusItems()
        defer {
            NSStatusBar.system.removeStatusItem(toggle)
            NSStatusBar.system.removeStatusItem(divider)
            permissionWindow?.close()
        }
        assert(!isCollapsed)
        collapse()
        assert(!isCollapsed && divider.length == 14)
        showPanel()
        assert(!isPanelOpen && permissionWindow?.isVisible == true)
        assert(settingsWindow == nil)
        testTrusted = true
        reconcileAccessibility()
        assert(accessibilityReady && isCollapsed && divider.length > 14)
        assert(permissionWindow?.isVisible == false)
        testTrusted = false
        reconcileAccessibility()
        assert(!accessibilityReady && !isCollapsed && divider.length == 14)
        assert(!isPanelOpen && permissionWindow?.isVisible == true)
        collapse()
        assert(!isCollapsed && divider.length == 14)
        print("PASS: denied launch/click stays visible; grant activates; revoke restores; collapse remains gated.")
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
    subprocess.run(['xcrun','swiftc','-swift-version','5','-framework','AppKit','-framework','ApplicationServices','-framework','ServiceManagement',str(path/'main.swift'),str(root/'SingleInstance.swift'),'-o',str(path/'test')],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    subprocess.run([str(path/'test')],check=True)
