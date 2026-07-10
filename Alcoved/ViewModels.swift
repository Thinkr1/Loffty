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
    
    func start() {}
    
    func setExpanded(_ v:Bool){
        guard v != isExpanded else {return}
        withAnimation(.spring(response:0.35, dampingFraction: 0.72)) {
            isExpanded=v
        }
    }
    
    func playPause() {}
    func next() {}
    func prev() {}
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
    private let notchMargin: CGFloat = 0
    private var w: CGFloat { vm.isExpanded ? 380 : collapsedWidth }
    private var h: CGFloat { vm.isExpanded ? 150 : collapsedHeight }
    private var collapsedWidth: CGFloat {
        let n = vm.notch.notchRect.width
        return n > 0 ? n + notchMargin : 200
    }
    private var collapsedHeight: CGFloat {
        let n = vm.notch.notchRect.height
        return n > 0 ? n + notchMargin : 32
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            NotchShape().fill(Color.black)
                .frame(width: w, height: h)
                .overlay {
                    if vm.isExpanded { ExpandedContent() } else { CollapsedContent() }
                }
                .shadow(radius: vm.isExpanded ? 12 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: vm.isExpanded)
    }
}

struct CollapsedContent: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack {
            artwork(size: 18)
            Spacer()
            if vm.nowPlaying.isPlaying {
                Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 8)
    }
    @ViewBuilder func artwork(size: CGFloat) -> some View {
        if let d = vm.nowPlaying.artwork, let img = NSImage(data: d) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
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
