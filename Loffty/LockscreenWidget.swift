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
    static let shared = LockScreenSpace()
    private let levelAboveLockScreen: Int32 = 300

    private typealias F_MainConnectionID = @convention(c) () -> Int32
    private typealias F_SpaceCreate =
        @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SpaceSetAbsoluteLevel =
        @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_AddWindowsAndRemove =
        @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let addWindowsAndRemove: F_AddWindowsAndRemove?
    private let connection: Int32
    private let space: Int32
    let isAvailable: Bool

    private init() {
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
        let showSpaces = sym("SLSShowSpaces", F_ShowSpaces.self)
        addWindowsAndRemove = sym(
            "SLSSpaceAddWindowsAndRemoveFromSpaces",
            F_AddWindowsAndRemove.self
        )

        guard let mainConnectionID, let spaceCreate, let spaceSetAbsoluteLevel,
            let showSpaces, addWindowsAndRemove != nil
        else {
            connection = 0
            space = 0
            isAvailable = false
            return
        }
        let cid = mainConnectionID()
        let sid = spaceCreate(cid, 1, 0)
        _ = spaceSetAbsoluteLevel(cid, sid, levelAboveLockScreen)
        _ = showSpaces(cid, [sid] as CFArray)
        connection = cid
        space = sid
        isAvailable = true
    }

    func add(_ window: NSWindow) {
        guard isAvailable, let addWindowsAndRemove else { return }
        _ = addWindowsAndRemove(
            connection,
            space,
            [window.windowNumber] as CFArray,
            7
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

private final class MovableHostingView<Content: View>: NSHostingView<Content> {
    var allowsWindowDrag = false

    override var mouseDownCanMoveWindow: Bool {
        allowsWindowDrag
    }
}

private final class MovableHostingController<Content: View>:
    NSHostingController<
        Content
    >
{
    var allowsWindowDrag = false {
        didSet { hostingView.allowsWindowDrag = allowsWindowDrag }
    }

    private var hostingView: MovableHostingView<Content> {
        view as! MovableHostingView<Content>
    }

    init(rootView: Content, allowsWindowDrag: Bool = false) {
        self.allowsWindowDrag = allowsWindowDrag
        super.init(rootView: rootView)
        let hostingView = MovableHostingView(rootView: rootView)
        hostingView.allowsWindowDrag = allowsWindowDrag
        view = hostingView
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LockScreenWidget {
    private let vm: NotchViewModel
    private weak var sourceNotchWindow: NotchWindow?
    private let lock = LockWatcher()

    private var lockNotchWindow: SkyPanel?
    private var cardWindow: SkyPanel?
    private var cardController: MovableHostingController<LockCardRootView>?
    private var lockNotchDelegated = false
    private var cardDelegated = false
    private var cancellables = Set<AnyCancellable>()

    init(vm: NotchViewModel, notchWindow: NotchWindow) {
        self.vm = vm
        self.sourceNotchWindow = notchWindow
    }

    func start() {
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

        lock.onChange = { [weak self] locked in
            guard let self else { return }
            if locked {
                self.vm.setExpanded(false)
                self.vm.setLocked(true)
                if AppSettings.shared.lockScreenNotch {
                    self.showLockNotch()
                }
                self.showCard()
            } else {
                self.vm.setLocked(false)
                self.setNotchInteractive(false)
                self.hideLockNotch()
                self.hideCard()
            }
        }
        lock.start()
    }

    func setNotchInteractive(_ interactive: Bool) {
        lockNotchWindow?.ignoresMouseEvents = !interactive
    }

    private func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
    }

    private func applyMovableSetting(_ movable: Bool) {
        cardWindow?.applyMovable(movable)
        cardController?.allowsWindowDrag = movable
    }

    private func hideCard() {
        cardWindow?.orderOut(nil)
    }

    private func hideLockNotch() {
        lockNotchWindow?.orderOut(nil)
    }

    private func showLockNotch() {
        let win = lockNotchWindow ?? makeLockNotchWindow()
        lockNotchWindow = win
        if let source = sourceNotchWindow {
            win.setFrame(source.frame, display: true)
        }
        win.orderFrontRegardless()
        if !lockNotchDelegated {
            LockScreenSpace.shared.add(win)
            lockNotchDelegated = true
        }
    }

    private func showCard() {
        guard vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty
        else { return }
        let win = cardWindow ?? makeCardWindow()
        cardWindow = win
        win.orderFrontRegardless()
        if !cardDelegated {
            LockScreenSpace.shared.add(win)
            cardDelegated = true
        }
    }

    private func resetCardPosition() {
        cardWindow?.setFrame(
            Self.defaultCardFrame(for: targetScreen()),
            display: true
        )
    }

    private static func defaultCardFrame(for screen: NSScreen) -> NSRect {
        let size = NSSize(width: 356, height: 174)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.19,
            width: size.width,
            height: size.height
        )
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
        let frame = Self.defaultCardFrame(for: targetScreen())
        let win = SkyPanel(frame: frame, movableByBackground: movable)
        win.hasShadow = false
        let controller = MovableHostingController(
            rootView: LockCardRootView(vm: vm),
            allowsWindowDrag: movable
        )
        win.contentViewController = controller
        cardController = controller
        return win
    }
}

private struct LockCardRootView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        LockCardView().environmentObject(vm)
    }
}

struct LockCardView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared

    private let cardShape = RoundedRectangle(
        cornerRadius: 38,
        style: .continuous
    )

    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Not playing" : vm.nowPlaying.title
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    if vm.nowPlaying.artwork != nil
                        || !vm.nowPlaying.artworkUnavailable
                    {
                        ArtworkThumbnail(
                            artwork: vm.nowPlaying.artwork,
                            unavailable: vm.nowPlaying.artworkUnavailable,
                            size: 58,
                            cornerRadius: 14,
                            trackKey: vm.nowPlaying.trackKey,
                            bundleIdentifier: vm.nowPlaying.bundleIdentifier,
                            showPlayerBadge: settings.playerBadgeLockScreen
                        )
                        .shadow(
                            color: .black.opacity(0.28),
                            radius: 10,
                            y: 4
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
                MediaProgressRow(accent: vm.accentColor).frame(maxWidth: 310)
                    .padding(.bottom, -5)
                MediaTransportControls()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.clear, in: cardShape)
            .overlay {
                cardShape
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
                cardShape
                    .strokeBorder(
                        .white.opacity(0.06),
                        lineWidth: 6
                    )
                    .blur(radius: 8)
                    .clipShape(cardShape)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        }
        .frame(width: 356, height: 174)
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: vm.nowPlaying.trackKey
        )
        .animation(
            .easeInOut(duration: 0.28),
            value: vm.nowPlaying.isPlaying
        )
    }
}
