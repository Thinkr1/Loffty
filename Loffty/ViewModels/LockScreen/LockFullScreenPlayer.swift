//
//  LockFullScreenPlayer.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 08/11/2026.
//

import AppKit
import SwiftUI

struct LockPlayerBackdrop: View {
    let artwork: Data?
    let accent: Color

    @State private var image: NSImage?

    private let sampleSide: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.35
            ZStack {
                Color.black
                accent.opacity(0.4)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: sampleSide, height: sampleSide)
                        .clipped()
                        .blur(radius: 5)
                        .saturation(1.6)
                        .drawingGroup()
                        .scaleEffect(side / sampleSide)
                        .opacity(0.9)
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                }
                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .animation(
            .easeInOut(duration: 0.7),
            value: image.map(ObjectIdentifier.init)
        )
        .task(id: artwork) {
            guard let artwork else {
                image = nil
                return
            }
            image = await ArtworkImageCache.image(for: artwork)
        }
    }
}

extension View {
    @ViewBuilder
    func lockPlayerButtonGlass() -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular.interactive(), in: Circle())
            } else {
                lockPlayerButtonFallback()
            }
        #else
            lockPlayerButtonFallback()
        #endif
    }

    fileprivate func lockPlayerButtonFallback() -> some View {
        self
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}

struct LockLyricsView: View {
    @ObservedObject var vm: NotchViewModel
    var isActive: Bool

    @ObservedObject private var store = LyricsStore.shared
    @State private var userScrolledAt = Date.distantPast

    private var trackIdentity: String {
        "\(vm.nowPlaying.artist)|\(vm.nowPlaying.title)|\(vm.nowPlaying.album)"
    }

    private var stateKey: String {
        switch store.state {
        case .idle: "idle"
        case .loading: "loading"
        case .unavailable: "unavailable"
        case .loaded: "loaded|\(trackIdentity)"
        }
    }

    var body: some View {
        ZStack {
            content
                .id(stateKey)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: stateKey)
        .mask(edgeFade)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: isActive) { _, _ in loadIfNeeded() }
        .onChange(of: trackIdentity) { _, _ in loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch store.state {
            case .loaded(let lyrics):
                if lyrics.isSynced {
                    syncedLyrics(lyrics.lines)
                } else {
                    plainLyrics(lyrics.lines)
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle, .unavailable:
                Text("No lyrics available")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
            }
        }
    }

    private func loadIfNeeded() {
        guard isActive else { return }
        store.load(for: vm.nowPlaying)
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var isUserScrolling: Bool {
        Date().timeIntervalSince(userScrolledAt) < 3
    }

    private func syncedLyrics(_ lines: [LyricLine]) -> some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                let active = LyricsParsing.activeIndex(
                    in: lines,
                    at: vm.currentTime(at: context.date)
                )
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            Color.clear.frame(height: geo.size.height * 0.32)
                            ForEach(lines) { line in
                                LockLyricLineView(
                                    line: line,
                                    distance: active.map { line.id - $0 },
                                    sharp: isUserScrolling
                                )
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    userScrolledAt = .distantPast
                                    vm.seek(to: line.time)
                                }
                            }
                            Color.clear.frame(height: geo.size.height * 0.6)
                        }
                        .padding(.trailing, 24)
                    }
                    .scrollIndicators(.never)
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .decelerating {
                            userScrolledAt = Date()
                        }
                    }
                    .onAppear {
                        if let active { proxy.scrollTo(active, anchor: anchor) }
                    }
                    .onChange(of: active) { _, newValue in
                        guard let newValue, !isUserScrolling else { return }
                        withAnimation(
                            .spring(response: 0.7, dampingFraction: 0.88)
                        ) {
                            proxy.scrollTo(newValue, anchor: anchor)
                        }
                    }
                }
            }
        }
    }

    private var anchor: UnitPoint { UnitPoint(x: 0, y: 0.32) }

    private func plainLyrics(_ lines: [LyricLine]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                Color.clear.frame(height: 60)
                ForEach(lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.trailing, 24)
        }
        .scrollIndicators(.never)
    }
}

private struct LockLyricLineView: View {
    let line: LyricLine
    let distance: Int?
    let sharp: Bool

    private var isActive: Bool { distance == 0 }

    private var blur: CGFloat {
        guard !sharp, let distance, distance != 0 else { return 0 }
        return min(CGFloat(abs(distance)), 4) * 0.9
    }

    var body: some View {
        Group {
            if line.isBreak {
                Text("•  •  •")
                    .font(.system(size: 24, weight: .heavy))
            } else {
                Text(line.text)
                    .font(.system(size: 32, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white.opacity(isActive ? 1 : 0.34))
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isActive ? 1 : 0.97, anchor: .leading)
        .blur(radius: blur)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.86),
            value: isActive
        )
        .animation(.easeOut(duration: 0.4), value: blur)
    }
}
