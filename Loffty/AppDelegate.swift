//
//  AppDelegate.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import Combine
import SwiftUI

final class NotchWindow: NSPanel {
    var acceptsInteraction = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 5
        )
        collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { acceptsInteraction }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    private var window: NSWindow?

    func prewarm() {
        ensureWindow()
        guard let window, let content = window.contentView else { return }
        content.frame = NSRect(x: 0, y: 0, width: 400, height: 520)
        content.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
    }

    func open() {
        ensureWindow()
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Loffty Settings"
        let hosting = NSHostingView(rootView: SettingsView())
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 520)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.animationBehavior = .none
        w.isRestorable = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window = w
    }
}

struct NotchInfo {
    let screen: NSScreen
    let notchRect: CGRect
}

func detectNotch(on screen: NSScreen) -> NotchInfo {
    let frame = screen.frame
    let topInset = screen.safeAreaInsets.top
    if topInset > 0, let left = screen.auxiliaryTopLeftArea,
        let right = screen.auxiliaryTopRightArea
    {
        let width = frame.width - left.width - right.width
        let height = topInset
        let x = frame.minX + left.width
        let y = frame.maxY - height
        return NotchInfo(
            screen: screen,
            notchRect: CGRect(x: x, y: y, width: width, height: height)
        )
    }
    let w: CGFloat = 220
    let h: CGFloat = 32
    let rect = CGRect(
        x: frame.midX - w / 2,
        y: frame.maxY - h,
        width: w,
        height: h
    )
    return NotchInfo(screen: screen, notchRect: rect)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow!
    private var airDropCatch: NSPanel!
    private var statusItem: NSStatusItem!
    private let vm = NotchViewModel()
    private var lockWidget: LockScreenWidget!
    private var hoverExpanded = false
    private var mouseButtonDown = false
    private var triggerZone = CGRect.zero
    private var expandedZone = CGRect.zero
    private var airDropZone = CGRect.zero
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screen =
            NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen
            .main!
        let info = detectNotch(on: screen)
        vm.notch = info
        let bandw: CGFloat = 600
        let bandh: CGFloat = 260
        let rect = NSRect(
            x: info.notchRect.midX - bandw / 2,
            y: screen.frame.maxY - bandh,
            width: bandw,
            height: bandh
        )
        window = NotchWindow(contentRect: rect)
        window.contentView = NSHostingView(
            rootView: NotchRootView().environmentObject(vm)
        )
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        setupAirDropCatch(notch: info.notchRect, screen: screen)
        setupStatusItem()
        installHoverMonitor(screen: screen, notch: info.notchRect)
        vm.start()
        lockWidget = LockScreenWidget(vm: vm, notchWindow: window)
        lockWidget.start()
        MainActor.assumeIsolated {
            syncAirDropHUD(enabled: AppSettings.shared.airDropHUD)
            vm.$isLocked
                .receive(on: RunLoop.main)
                .sink { [weak self] locked in
                    guard let self, locked else { return }
                    self.setHoverExpanded(false)
                }
                .store(in: &cancellables)

            AppSettings.shared.$lockScreenExpandNotch
                .receive(on: RunLoop.main)
                .sink { [weak self] allowed in
                    guard let self, self.vm.isLocked, !allowed else { return }
                    self.setHoverExpanded(false)
                }
                .store(in: &cancellables)

            AppSettings.shared.$lockScreenNotch
                .receive(on: RunLoop.main)
                .sink { [weak self] enabled in
                    guard let self, self.vm.isLocked, !enabled else { return }
                    self.setHoverExpanded(false)
                }
                .store(in: &cancellables)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            SettingsOpener.shared.prewarm()
        }
    }

    private func setupAirDropCatch(notch: CGRect, screen: NSScreen) {
        let pad: CGFloat = 12
        airDropZone = CGRect(
            x: notch.minX - pad,
            y: notch.minY - 8,
            width: notch.width + pad * 2,
            height: notch.height + 16
        )
        let panel = NSPanel(
            contentRect: airDropZone,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 8
        )
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let catchView = AirDropCatchView(frame: .zero)
        catchView.autoresizingMask = [.width, .height]
        catchView.isEnabled = { AppSettings.shared.airDropHUD }
        catchView.onDragEnter = { [weak self] urls in
            Task { @MainActor in
                guard let self, AppSettings.shared.airDropHUD else { return }
                self.expandAirDropCatch(on: screen)
                AirDropController.shared.offer(urls: urls)
                self.airDropCatch.orderFrontRegardless()
            }
        }
        catchView.onDropURLs = { [weak self] urls in
            Task { @MainActor in
                guard let self, AppSettings.shared.airDropHUD else { return }
                AirDropController.shared.offer(urls: urls)
                self.setAirDropInteractive(true)
                self.airDropCatch.orderFrontRegardless()
            }
        }
        catchView.onDragExit = { [weak self] in
            Task { @MainActor in
                if !AirDropController.shared.phase.isActive {
                    self?.resetAirDropCatch()
                }
            }
        }
        panel.contentView = catchView
        panel.orderFrontRegardless()
        airDropCatch = panel
    }

    private func expandAirDropCatch(on screen: NSScreen) {
        let w: CGFloat = 420
        let h: CGFloat = 150
        let frame = NSRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.maxY - h,
            width: w,
            height: h
        )
        airDropCatch.setFrame(frame, display: true)
    }

    private func resetAirDropCatch() {
        airDropCatch.setFrame(airDropZone, display: true)
    }

    private func setAirDropInteractive(_ active: Bool) {
        if active {
            window.ignoresMouseEvents = false
            window.acceptsInteraction = true
            window.orderFrontRegardless()
            resetAirDropCatch()
            airDropCatch.orderFrontRegardless()
        } else if !hoverExpanded {
            window.ignoresMouseEvents = true
            window.acceptsInteraction = false
            resetAirDropCatch()
        }
    }

    private func syncAirDropHUD(enabled: Bool) {
        airDropCatch?.orderFrontRegardless()
        if enabled {
            AirDropController.shared.startReceiveMonitoring()
        } else {
            AirDropController.shared.stopReceiveMonitoring()
            AirDropController.shared.cancel()
            setAirDropInteractive(false)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "notch"
        )
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu

        MainActor.assumeIsolated {
            AppSettings.shared.$hideMenuBarItem
                .receive(on: RunLoop.main)
                .sink { [weak self] hidden in
                    self?.statusItem.isVisible = !hidden
                }
                .store(in: &cancellables)

            AppSettings.shared.$airDropHUD
                .receive(on: RunLoop.main)
                .sink { [weak self] enabled in
                    self?.syncAirDropHUD(enabled: enabled)
                }
                .store(in: &cancellables)

            AirDropController.shared.$phase
                .receive(on: RunLoop.main)
                .sink { [weak self] phase in
                    guard let self else { return }
                    if phase.isActive {
                        self.setAirDropInteractive(true)
                    } else {
                        self.resetAirDropCatch()
                        if !self.hoverExpanded {
                            self.window.ignoresMouseEvents = true
                            self.window.acceptsInteraction = false
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated {
            SettingsOpener.shared.open()
        }
    }

    private func installHoverMonitor(screen: NSScreen, notch: CGRect) {
        let pad: CGFloat = 10
        triggerZone = CGRect(
            x: notch.minX - pad,
            y: notch.minY - pad,
            width: notch.width + pad * 2,
            height: screen.frame.maxY - (notch.minY - pad)
        )
        let panelW: CGFloat = 390
        let panelH: CGFloat = 182
        let margin: CGFloat = 36
        expandedZone = CGRect(
            x: notch.midX - panelW / 2 - margin,
            y: screen.frame.maxY - panelH - margin,
            width: panelW + margin * 2,
            height: panelH + margin
        )

        let mouseHandler: (NSEvent) -> Void = { [weak self] _ in
            self?.updateHoverState()
        }
        NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved],
            handler: mouseHandler
        )
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
            mouseHandler($0)
            return $0
        }
        NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) {
            [weak self] _ in
            self?.mouseButtonDown = true
        }
        NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseUp, .rightMouseUp,
        ]) {
            [weak self] _ in
            self?.mouseButtonDown = false
            self?.updateHoverState()
        }
    }

    private func updateHoverState() {
        if AirDropController.shared.phase.isActive { return }
        if vm.isLocked, !Self.lockScreenExpandAllowed { return }

        if hoverExpanded {
            guard !expandedZone.contains(NSEvent.mouseLocation) else { return }
            guard !mouseButtonDown else { return }
            setHoverExpanded(false)
            return
        }

        guard triggerZone.contains(NSEvent.mouseLocation) else { return }
        setHoverExpanded(true)
    }

    private static var lockScreenExpandAllowed: Bool {
        AppSettings.shared.lockScreenNotch
            && AppSettings.shared.lockScreenExpandNotch
    }

    private func setHoverExpanded(_ expanded: Bool) {
        guard hoverExpanded != expanded else { return }
        if expanded, vm.isLocked, !Self.lockScreenExpandAllowed { return }
        hoverExpanded = expanded

        if vm.isLocked {
            window.ignoresMouseEvents = true
            window.acceptsInteraction = false
            lockWidget.setNotchInteractive(expanded)
        } else if AirDropController.shared.phase.isActive {
            window.ignoresMouseEvents = false
            window.acceptsInteraction = true
        } else {
            window.ignoresMouseEvents = !expanded
            window.acceptsInteraction = expanded
            if expanded { window.makeKey() }
        }
        Task { @MainActor in vm.setExpanded(expanded) }
    }
}
