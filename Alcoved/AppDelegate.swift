//
//  AppDelegate.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import SwiftUI
import AppKit

final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel=true
        level=NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow))+5)
        collectionBehavior=[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground=false
        isOpaque=false
        backgroundColor = .clear
        hasShadow=false
        titleVisibility = .hidden
        titlebarAppearsTransparent=true
    }
    override var canBecomeKey: Bool {false}
    override var canBecomeMain: Bool {false}
}

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    private lazy var hosting = NSHostingView(rootView: SettingsLink { EmptyView() })
    private lazy var window: NSWindow = {
        let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = hosting
        w.alphaValue = 0
        return w
    }()

    func open() {
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        Self.findButton(in: hosting)?.performClick(nil)
        window.orderOut(nil)
    }

    private static func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton {return button}
        for sub in view.subviews {
            if let found = findButton(in: sub) {return found}
        }
        return nil
    }
}

struct NotchInfo {
    let screen: NSScreen
    let notchRect: CGRect
    let hasNotch: Bool
}

func detectNotch(on screen: NSScreen)->NotchInfo {
    let frame=screen.frame
    let topInset=screen.safeAreaInsets.top
    if topInset>0, let left=screen.auxiliaryTopLeftArea, let right=screen.auxiliaryTopRightArea {
        let width=frame.width-left.width-right.width
        let height=topInset
        let x=frame.minX+left.width
        let y=frame.maxY-height
        return NotchInfo(screen: screen, notchRect: CGRect(x:x,y:y,width:width,height:height), hasNotch: true)
    }
    let w: CGFloat=220, h:CGFloat=32
    let rect=CGRect(x:frame.midX-w/2, y:frame.maxY-h,width:w,height:h)
    return NotchInfo(screen:screen,notchRect: rect,hasNotch: false)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow!
    private var statusItem: NSStatusItem!
    private let vm=NotchViewModel()
    private var expanded=false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screen=NSScreen.screens.first {$0.safeAreaInsets.top>0} ?? NSScreen.main!
        let info=detectNotch(on: screen)
        vm.notch=info
        let bandw:CGFloat=600, bandh: CGFloat=260
        let rect=NSRect(x: info.notchRect.midX-bandw/2,y:screen.frame.maxY-bandh,width:bandw,height:bandh)
        window=NotchWindow(contentRect: rect)
        window.contentView=NSHostingView(rootView: NotchRootView().environmentObject(vm))
        window.ignoresMouseEvents=true
        window.orderFrontRegardless()
        setupStatusItem()
        installHoverMonitor(screen: screen, notch:info.notchRect)
        vm.start()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image=NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "notch")
        let menu=NSMenu()
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu=menu
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated {
            SettingsOpener.shared.open()
        }
    }
    
    private func installHoverMonitor(screen:NSScreen,notch:CGRect){
        let pad:CGFloat=10
        let triggerZone=CGRect(x:notch.minX-pad,y:notch.minY-pad,width:notch.width+pad*2,height:screen.frame.maxY-(notch.minY-pad))
        let panelW:CGFloat=390, panelH:CGFloat=182, margin:CGFloat=24
        let expandedZone=CGRect(x:notch.midX-panelW/2-margin,y:screen.frame.maxY-panelH-margin,width:panelW+margin*2,height:panelH+margin)
        let handler:(NSEvent)->Void={[weak self] _ in
            guard let self else {return}
            let zone=self.expanded ? expandedZone : triggerZone
            let inside=zone.contains(NSEvent.mouseLocation)
            guard inside != self.expanded else {return}
            self.expanded=inside
            self.window.ignoresMouseEvents = !inside
            Task {@MainActor in self.vm.setExpanded(inside)}
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {handler($0);return $0}
    }
}
