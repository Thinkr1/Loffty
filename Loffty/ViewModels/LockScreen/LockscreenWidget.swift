//
//  LockscreenWidget.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import AppKit
import Combine
import SwiftUI

final class LockScreenSpace {
    static let interactive = LockScreenSpace(level: 300)

    private typealias F_MainConnectionID = @convention(c) () -> Int32
    private typealias F_SpaceCreate =
        @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias F_SpaceSetAbsoluteLevel =
        @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias F_ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias F_AddWindowsAndRemove =
        @convention(c) (Int32, UInt64, CFArray, Int) -> Void

    private let addWindowsAndRemove: F_AddWindowsAndRemove?
    private let showSpaces: F_ShowSpaces?
    private let connection: Int32
    private let space: UInt64
    let isAvailable: Bool

    private init(level: Int32) {
        let path =
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        let handle = dlopen(path, RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        let mainConnectionID = sym(
            "SLSMainConnectionID",
            F_MainConnectionID.self
        )
        let spaceCreate = sym("SLSSpaceCreate", F_SpaceCreate.self)
        let spaceSetAbsoluteLevel = sym(
            "SLSSpaceSetAbsoluteLevel",
            F_SpaceSetAbsoluteLevel.self
        )
        showSpaces = sym("SLSShowSpaces", F_ShowSpaces.self)
        addWindowsAndRemove = sym(
            "SLSSpaceAddWindowsAndRemoveFromSpaces",
            F_AddWindowsAndRemove.self
        )

        guard let mainConnectionID, let spaceCreate,
            let spaceSetAbsoluteLevel, let showSpaces,
            addWindowsAndRemove != nil
        else {
            connection = 0
            space = 0
            isAvailable = false
            return
        }
        let cid = mainConnectionID()
        let sid = spaceCreate(cid, 1, 0)
        _ = spaceSetAbsoluteLevel(cid, sid, level)
        showSpaces(cid, [NSNumber(value: sid)] as CFArray)
        connection = cid
        space = sid
        isAvailable = sid != 0
    }

    func ensureShown() {
        guard isAvailable, let showSpaces, space != 0 else { return }
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
    }

    func add(_ window: NSWindow) {
        guard isAvailable, let addWindowsAndRemove, space != 0 else { return }
        let number = window.windowNumber
        guard number > 0 else { return }
        addWindowsAndRemove(
            connection,
            space,
            [NSNumber(value: number)] as CFArray,
            0x80007
        )
    }
}

final class SkyPanel: NSPanel {
    init(frame: NSRect, movableByBackground: Bool = false) {
        super.init(
            contentRect: frame,
            styleMask: [
                .borderless, .nonactivatingPanel, .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        applyMovable(movableByBackground)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        canBecomeVisibleWithoutLogin = true
        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
    }

    func applyMovable(_ movable: Bool) {
        isMovable = movable
        isMovableByWindowBackground = movable
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockCardHostingView<Content: View>: NSHostingView<Content> {
    var allowsWindowDrag = false
    var hitRect: CGRect = .null
    var hitsFullWindow = true

    override var mouseDownCanMoveWindow: Bool { allowsWindowDrag }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if hitsFullWindow || hitRect.isNull || hitRect.isEmpty {
            return super.hitTest(point)
        }
        let topLeftPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        guard hitRect.contains(topLeftPoint) else { return nil }
        return super.hitTest(point)
    }

    deinit {}
}

private final class LockCardHostingController<Content: View>:
    NSHostingController<Content>
{
    var allowsWindowDrag = false {
        didSet { hostingView.allowsWindowDrag = allowsWindowDrag }
    }

    private var hostingView: LockCardHostingView<Content> {
        view as! LockCardHostingView<Content>
    }

    override init(rootView: Content) {
        super.init(rootView: rootView)
        let hostingView = LockCardHostingView(rootView: rootView)
        hostingView.allowsWindowDrag = allowsWindowDrag
        view = hostingView
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHitRegion(cardRect: CGRect, hitsFullWindow: Bool) {
        hostingView.hitRect = cardRect
        hostingView.hitsFullWindow = hitsFullWindow
    }

    deinit {}
}

@MainActor
final class LockScreenWidget {
    private let vm: NotchViewModel
    private weak var sourceNotchWindow: NotchWindow?
    private let lock = LockWatcher()

    private var lockNotchWindow: SkyPanel?
    private var cardWindow: SkyPanel?
    private var accessoriesWindow: SkyPanel?
    private var cardController: LockCardHostingController<LockCardRootView>?
    private let placement = LockCardPlacement()
    private var savedCompactFrame: NSRect?
    private var cachedCardFrame: NSRect?
    private var appliedCachedFrameThisLock = false
    private var cancellables = Set<AnyCancellable>()

    init(vm: NotchViewModel, notchWindow: NotchWindow) {
        self.vm = vm
        self.sourceNotchWindow = notchWindow
    }

    func start() {
        _ = LockScreenSpace.interactive.isAvailable
        cachedCardFrame = Self.defaultCardFrame(for: targetScreen())

        AppSettings.shared.$movableWidget
            .receive(on: RunLoop.main)
            .sink { [weak self] movable in
                self?.applyMovableSetting(movable)
            }
            .store(in: &cancellables)

        AppSettings.shared.$widgetPositionResetToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetCardPosition()
            }
            .store(in: &cancellables)

        AppSettings.shared.$lockScreenNotch
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self, self.vm.isLocked else { return }
                if enabled {
                    self.showLockNotch()
                } else {
                    self.hideLockNotch()
                    self.vm.setExpanded(false)
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$lockScreenExpandNotch
            .receive(on: RunLoop.main)
            .sink { [weak self] allowed in
                guard let self, self.vm.isLocked else { return }
                if !allowed {
                    self.vm.setExpanded(false)
                    self.setNotchInteractive(false)
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$lockScreenFullScreenArt
            .receive(on: RunLoop.main)
            .sink { [weak self] allowed in
                guard let self, self.vm.isLocked, !allowed else { return }
                self.vm.setLockScreenArtExpanded(false)
                self.restoreCompactWindowFrameIfNeeded()
            }
            .store(in: &cancellables)

        let accessoryHeightTriggers = [
            AppSettings.shared.$lockScreenWeatherAccessory
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenBluetoothAccessory
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenBatteryAccessory
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenFocusAccessory
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenWeatherShowGraph
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenWeatherGraphKind
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenWeatherShowGraphLabels
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenAccessoryOrder
                .map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$lockScreenAccessoriesTopInsetFraction
                .map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(accessoryHeightTriggers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.syncAccessoriesIfNeeded()
            }
            .store(in: &cancellables)

        vm.$lockScreenArtExpanded
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                if expanded {
                    guard self.vm.isLocked,
                        AppSettings.shared.lockScreenFullScreenArt
                    else { return }
                    self.hideAccessories()
                    self.showFullScreenArt()
                } else {
                    self.hideFullScreenArt()
                    if self.vm.isLocked {
                        self.showAccessories()
                    }
                }
            }
            .store(in: &cancellables)

        vm.$nowPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.vm.isLocked else { return }
                self.showCard()
            }
            .store(in: &cancellables)

        lock.onChange = { [weak self] locked in
            guard let self else { return }
            if locked {
                self.vm.setExpanded(false)
                self.vm.setLocked(true)
                self.presentLockUI()
                for delay in [0.08, 0.25, 0.55, 1.0] as [TimeInterval] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        [weak self] in
                        guard let self, self.vm.isLocked else { return }
                        self.presentLockUI()
                    }
                }
            } else {
                self.vm.setLocked(false)
                self.setNotchInteractive(false)
                self.hideLockNotch()
                self.hideAccessories()
                self.hideCard()
                self.appliedCachedFrameThisLock = false
                if let frame = self.cardWindow?.frame {
                    self.cachedCardFrame = frame
                } else {
                    self.cachedCardFrame =
                        Self.defaultCardFrame(for: self.targetScreen())
                }
            }
        }
        lock.start()
    }

    private func presentLockUI() {
        LockScreenSpace.interactive.ensureShown()
        if AppSettings.shared.lockScreenNotch {
            showLockNotch()
        }
        showAccessories()
        showCard()
    }

    func setNotchInteractive(_ interactive: Bool) {
        lockNotchWindow?.ignoresMouseEvents = !interactive
    }

    private func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
    }

    private func applyMovableSetting(_ movable: Bool) {
        guard !vm.lockScreenArtExpanded else { return }
        cardWindow?.applyMovable(movable)
        cardController?.allowsWindowDrag = movable
    }

    private func hideCard() {
        cardWindow?.orderOut(nil)
        placement.isFlying = false
        vm.setLockScreenArtExpanded(false)
        restoreCompactWindowFrameIfNeeded()
    }

    private func hideLockNotch() {
        lockNotchWindow?.orderOut(nil)
    }

    private func hideAccessories() {
        accessoriesWindow?.orderOut(nil)
        LockAccessoryStatus.shared.stop()
    }

    private func showAccessories() {
        guard !vm.lockScreenArtExpanded else { return }
        let height = LockAccessoriesMetrics.height()
        guard height > 0 else {
            hideAccessories()
            return
        }
        let frame = Self.defaultAccessoriesFrame(for: targetScreen())
        let win = accessoriesWindow ?? makeAccessoriesWindow(frame: frame)
        accessoriesWindow = win
        win.setFrame(frame, display: true)
        win.alphaValue = 1
        win.ignoresMouseEvents = true
        win.orderFrontRegardless()
        LockScreenSpace.interactive.ensureShown()
        LockScreenSpace.interactive.add(win)
        LockAccessoryStatus.shared.start()
    }

    private func syncAccessoriesIfNeeded() {
        guard vm.isLocked, !vm.lockScreenArtExpanded else { return }
        showAccessories()
    }

    private func showLockNotch() {
        let win = lockNotchWindow ?? makeLockNotchWindow()
        lockNotchWindow = win
        if let source = sourceNotchWindow {
            win.setFrame(source.frame, display: true)
        }
        win.alphaValue = 1
        win.orderFrontRegardless()
        LockScreenSpace.interactive.add(win)
    }

    private func showCard() {
        let win = cardWindow ?? makeCardWindow()
        cardWindow = win
        if !vm.lockScreenArtExpanded {
            if !appliedCachedFrameThisLock {
                let frame =
                    cachedCardFrame
                    ?? Self.defaultCardFrame(for: targetScreen())
                win.setFrame(frame, display: true)
                appliedCachedFrameThisLock = true
            }
            win.alphaValue = 1
            win.ignoresMouseEvents = false
            win.orderFrontRegardless()
            win.displayIfNeeded()
            cardController?.updateHitRegion(
                cardRect: .null,
                hitsFullWindow: true
            )
        }
        LockScreenSpace.interactive.ensureShown()
        LockScreenSpace.interactive.add(win)
    }

    private func showFullScreenArt() {
        guard let cardWindow else { return }
        let screen = targetScreen()

        let alreadyFull =
            abs(cardWindow.frame.width - screen.frame.width) < 1
            && abs(cardWindow.frame.height - screen.frame.height) < 1
        if !alreadyFull {
            let compactFrame = cardWindow.frame
            savedCompactFrame = compactFrame
            placement.compactRect = Self.convert(
                compactFrame,
                toLocalTopLeftIn: screen.frame
            )
            cardWindow.setFrame(screen.frame, display: true)
        }

        cardWindow.ignoresMouseEvents = true
        cardWindow.applyMovable(false)
        cardController?.allowsWindowDrag = false
        placement.isFlying = true
        DispatchQueue.main.async { [weak self] in
            self?.placement.requestExpand()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard self?.vm.lockScreenArtExpanded == true else { return }
            self?.cardWindow?.ignoresMouseEvents = false
        }
    }

    private func hideFullScreenArt() {
        guard let cardWindow else { return }

        cardWindow.ignoresMouseEvents = false
        cardWindow.applyMovable(false)
        cardController?.allowsWindowDrag = false
        cardController?.updateHitRegion(
            cardRect: placement.compactRect,
            hitsFullWindow: false
        )
    }

    private func restoreCompactWindowFrameIfNeeded() {
        guard let cardWindow else { return }
        let compact =
            savedCompactFrame
            ?? cachedCardFrame
            ?? Self.defaultCardFrame(for: targetScreen())
        savedCompactFrame = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardWindow.setFrame(compact, display: false)
        CATransaction.commit()
        cachedCardFrame = compact
        placement.compactRect = CGRect(origin: .zero, size: compact.size)
        placement.isFlying = false
        applyMovableSetting(AppSettings.shared.movableWidget)
        cardController?.updateHitRegion(cardRect: .null, hitsFullWindow: true)
    }

    private static func convert(
        _ rect: CGRect,
        toLocalTopLeftIn windowFrame: CGRect
    ) -> CGRect {
        LockScreenPolicy.convertToLocalTopLeft(rect, in: windowFrame)
    }

    private func resetCardPosition() {
        guard !placement.isFlying else { return }
        let frame = Self.defaultCardFrame(for: targetScreen())
        cachedCardFrame = frame
        cardWindow?.setFrame(frame, display: true)
    }

    private static func defaultCardFrame(for screen: NSScreen) -> NSRect {
        LockScreenPolicy.defaultCardFrame(screenFrame: screen.frame)
    }

    private static func defaultAccessoriesFrame(for screen: NSScreen) -> NSRect
    {
        LockScreenPolicy.defaultAccessoriesFrame(screenFrame: screen.frame)
    }

    private func makeLockNotchWindow() -> SkyPanel {
        let frame = sourceNotchWindow?.frame ?? .zero
        let win = SkyPanel(frame: frame)
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.contentView = NSHostingView(
            rootView: NotchRootView().environmentObject(vm)
        )
        return win
    }

    private func makeCardWindow() -> SkyPanel {
        let movable = AppSettings.shared.movableWidget
        let frame =
            cachedCardFrame ?? Self.defaultCardFrame(for: targetScreen())
        cachedCardFrame = frame
        let win = SkyPanel(frame: frame, movableByBackground: movable)
        win.hasShadow = false
        let controller = LockCardHostingController(
            rootView: LockCardRootView(
                vm: vm,
                placement: placement,
                onHitRegionChange: { [weak self] rect, hitsFull in
                    self?.cardController?.updateHitRegion(
                        cardRect: rect,
                        hitsFullWindow: hitsFull
                    )
                }
            )
        )
        controller.allowsWindowDrag = movable
        win.contentViewController = controller
        cardController = controller
        return win
    }

    private func makeAccessoriesWindow(frame: NSRect) -> SkyPanel {
        let win = SkyPanel(frame: frame)
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.contentView = NSHostingView(rootView: LockAccessoriesRootView())
        return win
    }
}

private struct LockCardRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var placement: LockCardPlacement
    var onHitRegionChange: (CGRect, Bool) -> Void

    var body: some View {
        if placement.isFlying {
            LockMorphCardView(
                vm: vm,
                placement: placement,
                onHitRegionChange: onHitRegionChange
            )
        } else {
            LockCardView()
                .environmentObject(vm)
        }
    }
}

enum LockCardMatchID {
    static let chrome = "lockCard.chrome"
    static let artwork = "lockCard.artwork"
    static let text = "lockCard.text"
    static let controls = "lockCard.controls"
}

struct LockCardView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        Group {
            #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    GlassEffectContainer { cardBody }
                } else {
                    cardBody
                }
            #else
                cardBody
            #endif
        }
        .frame(
            width: LockCardMetrics.width,
            height: LockCardMetrics.height
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: vm.nowPlaying.trackKey
        )
        .animation(
            .easeInOut(duration: 0.28),
            value: vm.nowPlaying.isPlaying
        )
    }

    private var cardBody: some View {
        LockCardBody {
            guard AppSettings.shared.lockScreenFullScreenArt else {
                return
            }
            vm.setLockScreenArtExpanded(true)
        }
    }
}

struct LockCardBody: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    var onArtworkTap: () -> Void
    var namespace: Namespace.ID? = nil
    var preferFullArtwork: Bool = false
    var showsArtwork: Bool = true
    var showsChrome: Bool = true

    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Not playing" : vm.nowPlaying.title
    }

    private var artworkData: Data? {
        if preferFullArtwork {
            return vm.nowPlaying.fullArtwork ?? vm.nowPlaying.artwork
        }
        return vm.nowPlaying.artwork
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: LockCardMetrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        let content = VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                if showsArtwork,
                    artworkData != nil || !vm.nowPlaying.artworkUnavailable
                {
                    ArtworkThumbnail(
                        artwork: artworkData,
                        unavailable: vm.nowPlaying.artworkUnavailable,
                        size: 58,
                        cornerRadius: 14,
                        trackKey: vm.nowPlaying.trackKey,
                        namespace: namespace,
                        matchedGeometryID: LockCardMatchID.artwork,
                        bundleIdentifier: vm.nowPlaying
                            .resolvedBundleIdentifier,
                        showPlayerBadge: settings.playerBadgeLockScreen,
                        aspectRatio: vm.nowPlaying.displayArtworkAspect,
                        websiteHost: vm.nowPlaying.websiteHost
                    )
                    .shadow(
                        color: .black.opacity(0.28),
                        radius: 10,
                        y: 4
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onArtworkTap)
                } else if !showsArtwork {
                    Color.clear
                        .frame(
                            width: 58 * vm.nowPlaying.displayArtworkAspect,
                            height: 58
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(
                        text: title,
                        font: .system(size: 15, weight: .semibold),
                        color: .white.opacity(0.96),
                        height: 18,
                        scrolling: settings.marqueeEnabled
                    )
                    if settings.showAlbum, !vm.nowPlaying.album.isEmpty {
                        MarqueeText(
                            text: vm.nowPlaying.album,
                            font: .system(size: 12, weight: .medium),
                            color: .white.opacity(0.38),
                            height: 14,
                            scrolling: settings.marqueeEnabled
                        )
                        .transition(
                            .opacity.combined(with: .move(edge: .top))
                        )
                    }
                    if !vm.nowPlaying.artist.isEmpty {
                        MarqueeText(
                            text: vm.nowPlaying.artist,
                            font: .system(size: 13, weight: .medium),
                            color: .white.opacity(0.52),
                            height: 16,
                            scrolling: settings.marqueeEnabled
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .lockMatchedGeometry(id: LockCardMatchID.text, in: namespace)
                .animation(
                    .spring(response: 0.36, dampingFraction: 0.86),
                    value: settings.showAlbum
                )

                if settings.lockScreenWaveforms {
                    WaveBars(
                        isPlaying: vm.nowPlaying.isPlaying,
                        barCount: 5,
                        maxHeight: 16,
                        tint: settings.lockScreenWaveformsAccent
                            ? vm.accentColor
                            : .white.opacity(0.72)
                    )
                    .padding(.trailing, 14)
                    .frame(width: 22)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.85))
                    )
                }
            }
            .animation(
                .spring(response: 0.36, dampingFraction: 0.86),
                value: settings.lockScreenWaveforms
            )

            VStack(spacing: 14) {
                MediaProgressRow(accent: vm.accentColor)
                    .frame(maxWidth: 310)
                    .padding(.bottom, -5)
                MediaTransportControls()
            }
            .lockMatchedGeometry(id: LockCardMatchID.controls, in: namespace)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )

        if showsChrome {
            content.lockWidgetChrome(cardShape)
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func lockMatchedGeometry(id: String, in namespace: Namespace.ID?)
        -> some View
    {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    private func lockCardGlassBackground<S: Shape>(_ shape: S)
        -> some View
    {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffect(.clear, in: shape)
            } else {
                lockCardMaterialBackground(shape)
            }
        #else
            lockCardMaterialBackground(shape)
        #endif
    }

    private func lockCardMaterialBackground<S: Shape>(_ shape: S) -> some View {
        self
            .background(Color.black.opacity(0.35), in: shape)
            .background(.ultraThinMaterial, in: shape)
    }

    func lockWidgetChrome<S: InsettableShape>(_ shape: S) -> some View {
        self
            .lockCardGlassBackground(shape)
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                .white.opacity(0.10),
                                .white.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        .white.opacity(0.06),
                        lineWidth: 6
                    )
                    .blur(radius: 8)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}
