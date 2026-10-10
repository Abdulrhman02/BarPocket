"""Render production LTR/RTL layouts and check drag coordinates without posting input."""
from pathlib import Path
import subprocess
import platform
import tempfile
import sys
root=Path(__file__).resolve().parents[1]
s=(root/'main.swift').read_text().split('MainActor.assumeIsolated { startApp() }')[0]
s=s.replace('AXIsProcessTrusted()', 'true')
s=s.replace('divider.button?.window?.frame','testDividerFrame')
s=s.replace('CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []','testWindows')
s=s.replace('down.post(tap: tap)','testEvents.append(down.location)').replace('dragged.post(tap: tap)','testEvents.append(dragged.location)').replace('up.post(tap: tap)','testEvents.append(up.location)').replace('restore.post(tap: .cghidEventTap)','_ = restore')
s=s.replace('Thread.sleep(forTimeInterval: 0.08)','')
s=s.replace('down.post(tap: .cghidEventTap)', 'testEvents.append(down.location)').replace('up.post(tap: .cghidEventTap)', 'testEvents.append(up.location)')
s=s.replace('snapshots.nativeWindows()', 'testNativeWindows()')
s=s.replace('CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []', 'testWindows')
s=s.replace('testDividerFrame.', 'testDividerFrame?.')
s=s.replace('divider.button?.window?.screen ?? NSScreen.main', 'NSScreen.main')
s+='''
private let testDividerFrame: CGRect? = CGRect(x: 200,y:0,width:320,height:30)
private var testWindows = [[String: Any]]()
private var testEvents = [CGPoint]()
private func testNativeWindows() -> [IconSnapshots.StatusWindow] {
    testWindows.map {
        IconSnapshots.StatusWindow(id:($0[kCGWindowNumber as String] as! NSNumber).uint32Value,
          pid:($0[kCGWindowOwnerPID as String] as! NSNumber).int32Value,
          frame:CGRect(dictionaryRepresentation:$0[kCGWindowBounds as String] as! CFDictionary)!)
    }
}
extension PocketController {
    func verifyRTL() {
        for (i,size) in [NSSize(width:18,height:12),NSSize(width:24,height:10),NSSize(width:18,height:18)].enumerated() {
            let ctx=CGContext(data:nil,width:Int(size.width*2),height:Int(size.height*2),bitsPerComponent:8,bytesPerRow:Int(size.width*8),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red:1,green:CGFloat(i)/3,blue:0,alpha:1))
            ctx.fill(CGRect(x:2,y:2,width:size.width*2-4,height:size.height*2-4))
            glyphs[String(i)]=NSImage(cgImage:ctx.makeImage()!,size:size)
        }
        extras = glyphs.keys.sorted().map { MenuExtra(element:AXUIElementCreateApplication(getpid()),pid:getpid(),name:$0,title:$0,id:$0,frame:.zero) }
        assert(!extras.isEmpty)
        for direction in [NSUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                NSApp.appearance=NSAppearance(named:appearance)
                let content=makePanelContent()
                content.userInterfaceLayoutDirection=direction
                let width=extras.reduce(CGFloat(15)) { $0 + max(26,(glyphs[$1.id].map(displayGlyph)?.size.width ?? 18)+8)+1 }
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:40),styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentView=content
                content.layoutSubtreeIfNeeded()
                let buttons=extras.map { panelButtons[$0.id]! }
                for (index,button) in buttons.enumerated() {
                    assert(button.tag==index && extras[button.tag].id==extras[index].id)
                    assert(button.gestureRecognizers.contains { $0 is NSPanGestureRecognizer })
                    assert(button.gestureRecognizers.contains { $0 is NSClickGestureRecognizer })
                    if index>0 { assert(button.frame.minX > buttons[index-1].frame.minX) }
                    assert(button.image?.isTemplate==false)
                }
                let row=buttons[0].superview!
                assert(abs(row.frame.width-(width-4))<1, "Panel should fit its row")
                let rep=content.bitmapImageRepForCachingDisplay(in:content.bounds)!
                content.cacheDisplay(in:content.bounds,to:rep)
                let name="\\(direction == .rightToLeft ? "rtl" : "ltr")-\\(appearance.rawValue).png"
                try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]+"/"+name))
                window.close()
            }
        }
        let screen=NSScreen.main!
        let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber
        let bounds=CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let y=bounds.minY
        func record(_ id:Int,_ rect:CGRect)->[String:Any] {
            [kCGWindowLayer as String:Int(kCGStatusWindowLevel),kCGWindowNumber as String:NSNumber(value:id),kCGWindowOwnerPID as String:NSNumber(value:getpid()),kCGWindowBounds as String:rect.dictionaryRepresentation]
        }
        let itemFrame=CGRect(x:800,y:y,width:30,height:30)
        testWindows=[record(1,CGRect(x:200,y:y,width:320,height:30)),record(2,itemFrame)]
        let item=MenuExtra(element:AXUIElementCreateApplication(getpid()),pid:getpid(),name:"test",title:"test",id:"test",frame:itemFrame)
        assert(postTargetedCommandDrag(extra:item,keepVisible:false))
        assert(testEvents.count==3 && testEvents[0].x > testEvents[1].x)
        assert(testEvents[1].x==206 && testEvents.allSatisfy { abs($0.y-(y+15))<1 })
        testEvents=[]
        testWindows=[record(1,CGRect(x:200,y:y,width:320,height:30)),record(2,CGRect(x:150,y:y,width:30,height:30))]
        let hidden=MenuExtra(element:item.element,pid:getpid(),name:"test",title:"test",id:"test",frame:CGRect(x:150,y:y,width:30,height:30))
        assert(postTargetedCommandDrag(extra:hidden,keepVisible:true))
        assert(testEvents[0].x < testEvents[1].x && testEvents[1].x==526)
        testEvents=[]
        let negativeFrame=CGRect(x:-600,y:-1502,width:24,height:30)
        testWindows=[record(3,negativeFrame),record(4,CGRect(x:-600,y:0,width:24,height:30))]
        let negative=MenuExtra(element:item.element,pid:getpid(),name:"test",title:"test",id:"negative",frame:negativeFrame)
        assert(clickVisibleExtra(negative))
        assert(testEvents.count==2 && testEvents.allSatisfy { $0.x == -588 && $0.y == -1487 }, "Click must match the correct display and accept negative origins")
        var popup=record(5,CGRect(x:-650,y:-1460,width:220,height:140))
        popup[kCGWindowLayer as String]=101
        var normal=record(6,CGRect(x:-650,y:-1460,width:220,height:140))
        normal[kCGWindowLayer as String]=0
        var otherDisplay=record(7,CGRect(x:-650,y:30,width:220,height:140))
        otherDisplay[kCGWindowLayer as String]=101
        testWindows=[popup,normal,otherDisplay]
        assert(popupIDs(near:negativeFrame)==Set([5]), "Only the native popup anchored on this display should hold activation")
        print("PASS: anchored popup matching excludes normal/other-display windows; native click on negative display coordinates; LTR/RTL light/dark layout, button identity, drag gestures, fitted width, leftward hide and rightward restore event coordinates.")
    }
}
MainActor.assumeIsolated { _=NSApplication.shared; PocketController().verifyRTL() }
'''
with tempfile.TemporaryDirectory(prefix='barpocket-layout-test-') as folder:
    folder=Path(folder)
    source=folder/'main.swift'
    source.write_text(s)
    binary=folder/'check'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-target',f'{platform.machine()}-apple-macosx14.0','-framework','AppKit','-framework','ApplicationServices','-framework','ScreenCaptureKit','-framework','ServiceManagement',str(source),str(root/'SingleInstance.swift'),str(root/'IconSnapshots.swift'),'-o',str(binary)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    output=Path(sys.argv[1]) if len(sys.argv)>1 else folder/'renders'
    output.mkdir(parents=True,exist_ok=True)
    subprocess.run([str(binary),str(output)],check=True)
