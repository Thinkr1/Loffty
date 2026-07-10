//
//  ViewModels.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

import SwiftUI
import Combine

struct NowPlaying: Equatable {
    var title: String=""
    var artist: String=""
    var album: String=""
    var isPlaying: Bool=false
    var artwork: Data?=nil
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var notch=NotchInfo(screen: NSScreen.main!, notchRect: .zero, hasNotch: false)
    @Published var isExpanded=false
    @Published var nowPlaying=NowPlaying()
    private let media=MediaController()
    private let volume=SystemVolumeWatcher()
    
    func start() {
        media.onUpdate={[weak self] np in
            Task {@MainActor in self?.nowPlaying=np}
        }
        media.start()
        volume.onChange={lvl in
            //TODO: HUD
        }
        volume.start()
    }
    
    func setExpanded(_ v:Bool){
        guard v != isExpanded else {return}
        withAnimation(.spring(response:0.35, dampingFraction: 0.72)) {
            isExpanded=v
        }
    }
    
    func playPause() {media.command(.togglePlayPause)}
    func next() {media.command(.next)}
    func prev() {media.command(.prev)}
}

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 12
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = cornerRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY),control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c),control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if vm.isExpanded {
                NotchShape().fill(Color.black)
                    .frame(width: 380, height: 150)
                    .overlay { ExpandedContent() }
                    .shadow(radius: 12)
            } else {
                CollapsedContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: vm.isExpanded)
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    private let side: CGFloat = 44
    private var notchW: CGFloat { vm.notch.notchRect.width > 0 ? vm.notch.notchRect.width : 200 }
    private var notchH: CGFloat { vm.notch.notchRect.height > 0 ? vm.notch.notchRect.height : 32 }
    private var hasTrack: Bool { vm.nowPlaying.artwork != nil || !vm.nowPlaying.title.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            artwork(size: notchH - 8)
                .frame(width: side, alignment: .trailing)
                .padding(.trailing, 6)
            Color.clear.frame(width: notchW, height: notchH)
            Group {
                if vm.nowPlaying.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: notchH)
    }

    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if hasTrack {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.4)).frame(width: size, height: size)
        }
    }
}

struct ExpandedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: 12) {
            artwork(size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.nowPlaying.title.isEmpty ? "Nothing playing" : vm.nowPlaying.title)
                    .font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(vm.nowPlaying.artist).font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                HStack(spacing: 18) {
                    button("backward.fill") { vm.prev() }
                    button(vm.nowPlaying.isPlaying ? "pause.fill" : "play.fill") { vm.playPause() }
                    button("forward.fill") { vm.next() }
                }.padding(.top, 4)
            }
            Spacer()
        }
        .padding(12)
    }
    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.4)).frame(width: size, height: size)
        }
    }
    func button(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 16)).foregroundStyle(.white) }
            .buttonStyle(.plain)
    }
}
