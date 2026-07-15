//
//  Artwork.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import SwiftUI

extension View {
    @ViewBuilder
    fileprivate func applyMatchedGeometry(
        id: String,
        in namespace: Namespace.ID?
    ) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

enum AlbumColor {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    static func accent(from data: Data?) -> Color {
        guard let data, let img = CIImage(data: data), img.extent.width > 0,
            let f = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: img,
                    kCIInputExtentKey: CIVector(cgRect: img.extent),
                ]
            ),
            let out = f.outputImage
        else { return Color.white.opacity(0.5) }
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(
            out,
            toBitmap: &px,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var color = NSColor(
            red: CGFloat(px[0]) / 255,
            green: CGFloat(px[1]) / 255,
            blue: CGFloat(px[2]) / 255,
            alpha: 1
        )
        if let c = color.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0
            var s: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            color = NSColor(
                hue: h,
                saturation: min(1, s * 1.7),
                brightness: max(b, 0.55),
                alpha: 1
            )
        }
        return Color(nsColor: color)
    }
}

private actor ArtworkImageStore {
    static let shared = ArtworkImageStore()
    private var cache: [Int: NSImage] = [:]
    private let maxEntries = 24

    func image(for data: Data) async -> NSImage? {
        let key = data.hashValue
        if let cached = cache[key] {
            return cached
        }

        let img = await Task.detached(priority: .userInitiated) {
            NSImage(data: data)
        }.value
        guard let img else { return nil }

        if cache.count >= maxEntries, let oldest = cache.keys.first {
            cache.removeValue(forKey: oldest)
        }
        cache[key] = img
        return img
    }
}

enum ArtworkImageCache {
    static func image(for data: Data) async -> NSImage? {
        await ArtworkImageStore.shared.image(for: data)
    }
}

struct ArtworkThumbnail: View {
    let artwork: Data?
    let unavailable: Bool
    let size: CGFloat
    var cornerRadius: CGFloat = 12
    var trackKey: String = ""
    var namespace: Namespace.ID? = nil

    var body: some View {
        ArtworkCrossfade(
            artwork: artwork,
            unavailable: unavailable,
            trackKey: trackKey,
            size: size,
            cornerRadius: cornerRadius,
            namespace: namespace
        )
    }
}

private struct ArtworkCrossfade: View {
    @EnvironmentObject private var vm: NotchViewModel
    let artwork: Data?
    let unavailable: Bool
    let trackKey: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let namespace: Namespace.ID?

    @State private var front: Data?
    @State private var back: Data?
    @State private var frontImage: NSImage?
    @State private var backImage: NSImage?
    @State private var blend: CGFloat = 1
    @State private var pop: CGFloat = 0
    @State private var loadGeneration = 0

    private var showsSlot: Bool {
        artwork != nil || !unavailable || front != nil || back != nil
    }

    private var loadingNewArt: Bool {
        artwork == nil && !unavailable && (front != nil || back != nil)
    }

    var body: some View {
        if showsSlot {
            ZStack {
                artworkImage(backImage)
                    .opacity(1 - blend)
                    .scaleEffect(0.985 + (1 - blend) * 0.015)
                    .blur(radius: blend < 1 ? (1 - blend) * 2.5 : 0)

                if let frontImage {
                    artworkImage(frontImage)
                        .opacity(blend)
                        .scaleEffect(0.965 + blend * 0.035)
                } else if !loadingNewArt {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(
                color: vm.accentColor.opacity(0.28 + pop * 0.22),
                radius: 8 + pop * 8,
                y: 3
            )
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            .scaleEffect(1 + pop * 0.045)
            .opacity(loadingNewArt ? 0.82 : 1)
            .applyMatchedGeometry(id: "artwork", in: namespace)
            .animation(.easeInOut(duration: 0.22), value: loadingNewArt)
            .onAppear { syncArtwork(animated: false) }
            .onChange(of: artwork) { _, _ in syncArtwork(animated: true) }
            .onChange(of: unavailable) { _, _ in syncArtwork(animated: true) }
            .onChange(of: trackKey) { _, _ in syncArtwork(animated: true) }
            .onChange(of: vm.trackChangeToken) { _, token in
                guard token > 0, !vm.isRapidSkipping else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.64)) {
                    pop = 1
                }
                withAnimation(.easeOut(duration: 0.38).delay(0.07)) {
                    pop = 0
                }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.gray.opacity(0.35))
    }

    @ViewBuilder
    private func artworkImage(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func syncArtwork(animated: Bool) {
        let useAnimation = animated && !vm.isRapidSkipping

        if unavailable, artwork == nil {
            guard front != nil || back != nil else { return }
            if useAnimation {
                withAnimation(.easeOut(duration: 0.28)) { blend = 0 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    front = nil
                    back = nil
                    frontImage = nil
                    backImage = nil
                    blend = 1
                }
            } else {
                front = nil
                back = nil
                frontImage = nil
                backImage = nil
                blend = 1
            }
            return
        }

        guard let artwork else { return }
        if front == artwork { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        Task {
            guard let image = await ArtworkImageCache.image(for: artwork) else {
                return
            }
            await MainActor.run {
                guard generation == loadGeneration else { return }
                applyLoadedArtwork(image, data: artwork, animated: useAnimation)
            }
        }
    }

    private func applyLoadedArtwork(
        _ image: NSImage,
        data: Data,
        animated: Bool
    ) {
        if front == data { return }

        if front == nil {
            front = data
            frontImage = image
            blend = 1
            return
        }

        guard animated else {
            front = data
            frontImage = image
            back = nil
            backImage = nil
            blend = 1
            return
        }

        back = front
        backImage = frontImage
        front = data
        frontImage = image
        blend = 0
        withAnimation(.easeInOut(duration: 0.42)) { blend = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(460))
            if front == data {
                back = nil
                backImage = nil
            }
        }
    }
}
