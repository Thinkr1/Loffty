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
    static let contentSize = NSSize(width: 700, height: 580)
    private var window: NSWindow?

    func prewarm() {
        ensureWindow()
        guard let window, let content = window.contentView else { return }
        content.frame = NSRect(origin: .zero, size: Self.contentSize)
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
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [
                .titled, .closable, .resizable, .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        w.title = "Loffty Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false
        w.backgroundColor = .clear
        w.isOpaque = false
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        let hosting = NSHostingView(rootView: SettingsView())
        hosting.frame = NSRect(origin: .zero, size: Self.contentSize)
        w.contentView = hosting
        w.contentMinSize = NSSize(width: 700, height: 560)
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

enum LockScreenPolicy {
    static func expandAllowed(
        lockScreenNotch: Bool,
        lockScreenExpandNotch: Bool
    ) -> Bool {
        lockScreenNotch && lockScreenExpandNotch
    }

    static func defaultCardFrame(screenFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: LockCardMetrics.width,
            height: LockCardMetrics.height
        )
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + screenFrame.height * 0.19,
            width: size.width,
            height: size.height
        )
    }

    static func convertToLocalTopLeft(
        _ rect: CGRect,
        in windowFrame: CGRect
    ) -> CGRect {
        let x = rect.minX - windowFrame.minX
        let y =
            windowFrame.height - (rect.minY - windowFrame.minY) - rect.height
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    static func resolvedCompactRect(
        windowSize: CGSize,
        placed: CGRect,
        cardWidth: CGFloat = LockCardMetrics.width,
        cardHeight: CGFloat = LockCardMetrics.height
    ) -> CGRect {
        if windowSize.width <= cardWidth + 0.5,
            windowSize.height <= cardHeight + 0.5
        {
            return CGRect(origin: .zero, size: windowSize)
        }
        if placed.width > 1, placed.height > 1 {
            return placed
        }
        return CGRect(
            x: max(0, (windowSize.width - cardWidth) / 2),
            y: max(0, (windowSize.height - cardHeight) / 2),
            width: cardWidth,
            height: cardHeight
        )
    }
}

func notchRect(
    screenFrame: CGRect,
    topInset: CGFloat,
    leftAuxWidth: CGFloat?,
    rightAuxWidth: CGFloat?
) -> CGRect {
    if topInset > 0, let left = leftAuxWidth, let right = rightAuxWidth {
        return CGRect(
            x: screenFrame.minX + left,
            y: screenFrame.maxY - topInset,
            width: screenFrame.width - left - right,
            height: topInset
        )
    }
    let w: CGFloat = 220
    let h: CGFloat = 32
    return CGRect(
        x: screenFrame.midX - w / 2,
        y: screenFrame.maxY - h,
        width: w,
        height: h
    )
}

func detectNotch(on screen: NSScreen) -> NotchInfo {
    let frame = screen.frame
    let topInset = screen.safeAreaInsets.top
    let left = screen.auxiliaryTopLeftArea.map(\.width)
    let right = screen.auxiliaryTopRightArea.map(\.width)
    return NotchInfo(
        screen: screen,
        notchRect: notchRect(
            screenFrame: frame,
            topInset: topInset,
            leftAuxWidth: left,
            rightAuxWidth: right
        )
    )
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow!
    private var airDropCatch: NSPanel!
    private var statusItem: NSStatusItem!
    private var vm: NotchViewModel!
    private var lockWidget: LockScreenWidget!
    private var hoverExpanded = false
    private var mouseButtonDown = false
    private var triggerZone = CGRect.zero
    private var expandedZone = CGRect.zero
    private var airDropZone = CGRect.zero
    private var cancellables = Set<AnyCancellable>()
    private let fullScreen = FullScreenWatcher()

    private nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
            != nil
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !Self.isRunningTests else { return }

        NSApp.setActivationPolicy(.accessory)
        guard
            let screen =
                NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main
        else { return }
        vm = NotchViewModel()
        let info = detectNotch(on: screen)
        vm.notch = info
        let bandw: CGFloat = 600
        let bandh: CGFloat = 300
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
        lockWidget = LockScreenWidget(vm: vm, notchWindow: window)
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

        fullScreen.onChange = { [weak self] isFullScreen, _ in
            self?.vm.isFullScreen = isFullScreen
            self?.syncFullScreenVisibility()
        }
        AppSettings.shared.$hideNotchInFullScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFullScreenMonitoring()
            }
            .store(in: &cancellables)
        AppSettings.shared.$hideNotchFullScreenApps
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFullScreenMonitoring()
            }
            .store(in: &cancellables)
        AppSettings.shared.$notchEdgeStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFullScreenMonitoring()
            }
            .store(in: &cancellables)
        AppSettings.shared.$notchOutlineWhenNotFullScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFullScreenMonitoring()
            }
            .store(in: &cancellables)
        vm.$hudDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFullScreenVisibility()
            }
            .store(in: &cancellables)

        if OnboardingFlow.shouldPresentOnboarding(
            hasCompletedOnboarding: AppSettings.shared.hasCompletedOnboarding
        ) {
            OnboardingOpener.shared.present { [weak self] in
                self?.beginNormalOperation()
            }
        } else {
            beginNormalOperation()
        }
    }

    private func beginNormalOperation() {
        vm.start()
        lockWidget.start()
        syncAirDropHUD(enabled: AppSettings.shared.airDropHUD)
        syncNotificationsHUD(enabled: AppSettings.shared.notificationsHUD)
        syncFullScreenMonitoring()
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            SettingsOpener.shared.prewarm()
            AppUpdater.shared.checkForUpdatesIfNeeded()
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
        catchView.isEnabled = {
            MainActor.assumeIsolated { AppSettings.shared.airDropHUD }
        }
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
            applyWindowInteraction(interactive: true)
            resetAirDropCatch()
            airDropCatch.orderFrontRegardless()
        } else {
            resetAirDropCatch()
            applyWindowInteraction()
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

    private func syncNotificationsHUD(enabled: Bool) {
        if enabled {
            NotificationController.shared.start()
        } else {
            NotificationController.shared.stop()
        }
        applyWindowInteraction()
    }

    private func applyWindowInteraction(interactive: Bool? = nil) {
        if shouldSuppressNotchForFullScreen {
            window.ignoresMouseEvents = true
            window.acceptsInteraction = false
            if window.isKeyWindow { window.resignKey() }
            fadeNotch(to: 0)
            return
        }

        fadeNotch(to: 1)
        let notes = NotificationController.shared
        let airDropActive = AirDropController.shared.phase.isActive
        let shouldInteract =
            interactive
            ?? (hoverExpanded || airDropActive
                || notes.wantsKeyWindow)

        if vm.isLocked {
            window.ignoresMouseEvents = true
            window.acceptsInteraction = false
            lockWidget.setNotchInteractive(hoverExpanded)
            return
        }

        window.ignoresMouseEvents = !shouldInteract
        window.acceptsInteraction = shouldInteract
        if notes.wantsKeyWindow {
            window.makeKey()
        } else if window.isKeyWindow, !hoverExpanded, !airDropActive {
            window.resignKey()
        }
        if shouldInteract {
            window.orderFrontRegardless()
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
            withTitle: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        #if DEBUG
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "Test WhatsApp Notification",
                action: #selector(previewWhatsAppNotification),
                keyEquivalent: "n"
            )
            menu.addItem(
                withTitle: "Test Messages Notification",
                action: #selector(previewMessagesNotification),
                keyEquivalent: ""
            )
            menu.addItem(
                withTitle: "Test Discord Notification",
                action: #selector(previewDiscordNotification),
                keyEquivalent: ""
            )
        #endif
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu

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

        AppSettings.shared.$notificationsHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.syncNotificationsHUD(enabled: enabled)
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
                    self.applyWindowInteraction()
                }
                self.syncFullScreenVisibility()
            }
            .store(in: &cancellables)

        NotificationController.shared.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateHoverState()
                self?.syncFullScreenVisibility()
            }
            .store(in: &cancellables)

        NotificationController.shared.$isReplying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyWindowInteraction()
            }
            .store(in: &cancellables)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {
                let notes = NotificationController.shared
                if notes.isActive {
                    Task { @MainActor in
                        notes.dismiss()
                        self?.applyWindowInteraction()
                    }
                    return nil
                }
            }
            return event
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsOpener.shared.open()
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdatesNow()
    }

    #if DEBUG
        @objc private func previewWhatsAppNotification() {
            NotificationController.shared.presentPreview(app: .whatsApp)
        }

        @objc private func previewMessagesNotification() {
            NotificationController.shared.presentPreview(app: .messages)
        }

        @objc private func previewDiscordNotification() {
            NotificationController.shared.presentPreview(app: .discord)
        }
    #endif

    private func installHoverMonitor(screen: NSScreen, notch: CGRect) {
        let pad: CGFloat = 10
        triggerZone = CGRect(
            x: notch.minX - pad,
            y: notch.minY - pad,
            width: notch.width + pad * 2,
            height: screen.frame.maxY - (notch.minY - pad)
        )
        let panelW: CGFloat = 392
        let panelH: CGFloat = 206
        let margin: CGFloat = 36
        expandedZone = CGRect(
            x: notch.midX - panelW / 2 - margin,
            y: screen.frame.maxY - panelH - margin,
            width: panelW + margin * 2,
            height: panelH + margin
        )

        let mouseHandler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverState()
            }
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
        ]) { [weak self] _ in
            Task { @MainActor in
                self?.mouseButtonDown = true
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseUp, .rightMouseUp,
        ]) { [weak self] _ in
            Task { @MainActor in
                self?.mouseButtonDown = false
                self?.updateHoverState()
            }
        }
    }

    private func updateHoverState() {
        if AirDropController.shared.phase.isActive { return }
        if vm.isLocked, !Self.lockScreenExpandAllowed { return }
        if shouldHidePersistentNotch, !NotificationController.shared.isActive {
            if hoverExpanded { setHoverExpanded(false) }
            applyWindowInteraction()
            return
        }

        let notes = NotificationController.shared
        if notes.isActive {
            let overExpanded = expandedZone.contains(NSEvent.mouseLocation)
            let overCompact = notificationCompactZone.contains(
                NSEvent.mouseLocation
            )
            if notes.isExpanded {
                if !overExpanded, !mouseButtonDown, !notes.isPinned {
                    notes.collapse()
                }
            }
            applyWindowInteraction(
                interactive: (notes.isExpanded ? overExpanded : overCompact)
                    || notes.wantsKeyWindow
            )
            return
        }

        if hoverExpanded {
            guard !expandedZone.contains(NSEvent.mouseLocation) else { return }
            guard !mouseButtonDown else { return }
            setHoverExpanded(false)
            return
        }

        guard triggerZone.contains(NSEvent.mouseLocation) else { return }
        setHoverExpanded(true)
    }

    private var notificationCompactZone: CGRect {
        triggerZone.insetBy(dx: -90, dy: -96)
    }

    private static var lockScreenExpandAllowed: Bool {
        LockScreenPolicy.expandAllowed(
            lockScreenNotch: AppSettings.shared.lockScreenNotch,
            lockScreenExpandNotch: AppSettings.shared.lockScreenExpandNotch
        )
    }

    private func setHoverExpanded(_ expanded: Bool) {
        guard hoverExpanded != expanded else { return }
        if expanded, vm.isLocked, !Self.lockScreenExpandAllowed { return }
        if expanded, shouldHidePersistentNotch { return }
        hoverExpanded = expanded

        if vm.isLocked {
            window.ignoresMouseEvents = true
            window.acceptsInteraction = false
            lockWidget.setNotchInteractive(expanded)
        } else {
            applyWindowInteraction()
        }
        vm.setExpanded(expanded)
    }

    private var shouldHidePersistentNotch: Bool {
        guard !vm.isLocked else { return false }
        return FullScreenPolicy.shouldHideNotch(
            hideInAnyFullScreen: AppSettings.shared.hideNotchInFullScreen,
            selectedBundleIDs: AppSettings.shared.hideNotchFullScreenApps,
            frontmostBundleID: fullScreen.frontmostBundleID,
            isFullScreen: fullScreen.isFullScreen
        )
    }

    private var overlayForcesNotchVisible: Bool {
        vm.hudDisplay != nil
            || AirDropController.shared.phase.isActive
            || NotificationController.shared.isActive
    }

    private var shouldSuppressNotchForFullScreen: Bool {
        shouldHidePersistentNotch && !overlayForcesNotchVisible
    }

    private func syncFullScreenMonitoring() {
        if AppSettings.shared.watchesFullScreenApps {
            fullScreen.start { [weak self] in
                self?.vm.notch.screen
            }
        } else {
            fullScreen.stop()
        }
        syncFullScreenVisibility()
    }

    private func syncFullScreenVisibility() {
        if shouldHidePersistentNotch, hoverExpanded {
            setHoverExpanded(false)
        }
        applyWindowInteraction()
    }

    private func fadeNotch(to alpha: CGFloat) {
        guard abs(window.alphaValue - alpha) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = alpha
        }
    }
}
