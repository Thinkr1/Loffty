//
//  LockscreenWidget.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import AppKit
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
    init(frame: NSRect) {
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
        isMovable = false
        //isMovableByWindowBackground=true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        canBecomeVisibleWithoutLogin = true
        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LockScreenWidget {
    private let vm: NotchViewModel
    private let lock = LockWatcher()

    private var notchWindow: SkyPanel?
    private var cardWindow: SkyPanel?
    private var notchDelegated = false
    private var cardDelegated = false

    init(vm: NotchViewModel) { self.vm = vm }

    func start() {
        lock.onChange = { [weak self] locked in
            guard let self else { return }
            if locked {
                self.showCard()
                self.vm.setLocked(true)
            } else {
                self.vm.setLocked(false)
                self.hideWindows()
            }
        }
        lock.start()
    }

    private func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
    }

    private func hideWindows() {
        notchWindow?.orderOut(nil)
        cardWindow?.orderOut(nil)
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

    private func makeCardWindow() -> SkyPanel {
        let screen = targetScreen()
        let size = NSSize(width: 350, height: 96)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.15,
            width: size.width,
            height: size.height
        )
        let win = SkyPanel(frame: frame)
        win.contentViewController = NSHostingController(
            rootView: LockCardView().environmentObject(vm)
        )
        return win
    }
}

struct LockCardView: View {
    @EnvironmentObject var vm: NotchViewModel
    private var title: String {
        vm.nowPlaying.title.isEmpty ? "Not playing" : vm.nowPlaying.title
    }

    var body: some View {
        GlassEffectContainer {
            VStack {
                HStack(spacing: 12) {
                    if vm.nowPlaying.artwork != nil
                        || !vm.nowPlaying.artworkUnavailable
                    {
                        ArtworkThumbnail(
                            artwork: vm.nowPlaying.artwork,
                            unavailable: vm.nowPlaying.artworkUnavailable,
                            size: 56,
                            cornerRadius: 12
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        if !vm.nowPlaying.artist.isEmpty {
                            Text(vm.nowPlaying.artist).font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                MediaProgressRow(accent: vm.accentColor).padding(.horizontal)
                MediaTransportControls().padding([.horizontal, .bottom])
            }
            .glassEffect(
                .clear,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .frame(width: 350, height: 250)
    }
}
