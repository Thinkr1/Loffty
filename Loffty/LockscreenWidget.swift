//
//  LockscreenWidget.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import SwiftUI
import AppKit

final class LockScreenSpace {
    static let shared = LockScreenSpace()
    private let levelAboveLockScreen: Int32 = 300
    
    private typealias F_MainConnectionID = @convention(c) () -> Int32
    private typealias F_SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_AddWindowsAndRemove = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    
    private let addWindowsAndRemove: F_AddWindowsAndRemove?
    private let connection: Int32
    private let space: Int32
    let isAvailable: Bool
    
    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        let handle = dlopen(path, RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        let mainConnectionID = sym("SLSMainConnectionID", F_MainConnectionID.self)
        let spaceCreate = sym("SLSSpaceCreate", F_SpaceCreate.self)
        let spaceSetAbsoluteLevel = sym("SLSSpaceSetAbsoluteLevel", F_SpaceSetAbsoluteLevel.self)
        let showSpaces = sym("SLSShowSpaces", F_ShowSpaces.self)
        addWindowsAndRemove = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", F_AddWindowsAndRemove.self)
        
        guard let mainConnectionID, let spaceCreate, let spaceSetAbsoluteLevel, let showSpaces,addWindowsAndRemove != nil else {
            connection = 0; space = 0; isAvailable = false; return
        }
        let cid = mainConnectionID()
        let sid = spaceCreate(cid, 1, 0)
        _ = spaceSetAbsoluteLevel(cid, sid, levelAboveLockScreen)
        _ = showSpaces(cid, [sid] as CFArray)
        connection = cid; space = sid; isAvailable = true
    }
    
    func add(_ window: NSWindow) {
        guard isAvailable, let addWindowsAndRemove else { return }
        _ = addWindowsAndRemove(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

final class SkyPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        //isMovableByWindowBackground=true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
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
        guard vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty else { return }
        let win = cardWindow ?? makeCardWindow()
        cardWindow = win
        win.orderFrontRegardless()
        if !cardDelegated { LockScreenSpace.shared.add(win); cardDelegated = true }
    }
    
    private func makeCardWindow() -> SkyPanel {
        let screen = targetScreen()
        let size = NSSize(width: 340, height: 96)
        let frame = NSRect(x: screen.frame.midX - size.width / 2,y: screen.frame.minY + screen.frame.height * 0.227,width: size.width, height: size.height)
        let win = SkyPanel(frame: frame)
        win.contentViewController = NSHostingController(rootView: LockCardView().environmentObject(vm))
        return win
    }
}

struct LockCardView: View {
    @EnvironmentObject var vm: NotchViewModel
    private var title: String { vm.nowPlaying.title.isEmpty ? "Not playing" : vm.nowPlaying.title }
    
    var body: some View {
        GlassEffectContainer {
            VStack{
                HStack(spacing: 12) {
                    artwork(size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Text(vm.nowPlaying.artist).font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                progressBar.padding(.horizontal)
                controls.padding([.horizontal, .bottom])
            }
            .glassEffect(.clear,in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: 340, height: 250)
    }
    
    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let cur = vm.currentTime(at: ctx.date)
            let dur = vm.nowPlaying.duration
            let p = dur > 0 ? min(1, max(0, cur / dur)) : 0
            let remaining = max(0, dur - cur)
            HStack(spacing: 10) {
                Text(fmtTime(cur))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(vm.accentColor.opacity(0.9)).frame(width: max(0, geo.size.width * p))
                    }
                }
                .frame(height: 6)
                Text(dur > 0 ? "-\(fmtTime(remaining))" : fmtTime(cur))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
        }
    }
    
    private var controls: some View {
        HStack(spacing: 0) {
            Spacer()
            sym("gobackward.10", 18, .white.opacity(0.8)) { vm.seek(by: -10) }.padding(.trailing, 12)
            sym("backward.fill", 20, .white) { vm.prev() }.padding(.trailing, 12)
            sym(vm.nowPlaying.isPlaying ? "pause.fill" : "play.fill", 24, .white) { vm.playPause() }.padding(.trailing, 12)
            sym("forward.fill", 20, .white) { vm.next() }.padding(.trailing, 12)
            sym("goforward.10", 18, .white.opacity(0.8)) { vm.seek(by: 10) }
            Spacer()
        }
        .padding(.horizontal, -4)
    }
    
    private func sym(_ name: String, _ size: CGFloat, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder private func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.15)).frame(width: size, height: size)
        }
    }
}
