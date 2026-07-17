//
//  Artwork.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 15/07/2026.
//

import AppKit
import CoreServices
import SwiftUI

enum ArtworkProcessor {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    static let maxPixel: CGFloat = 120

    static func thumbnailData(from data: Data) -> Data {
        guard
            let img = CIImage(data: data),
            max(img.extent.width, img.extent.height) > maxPixel
        else { return data }
        let scale = maxPixel / max(img.extent.width, img.extent.height)
        let scaled = img.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else {
            return data
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard
            let jpeg = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
            )
        else { return data }
        return jpeg
    }
}

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
        guard let data else { return Color.white.opacity(0.5) }
        guard var img = CIImage(data: data), img.extent.width > 0 else {
            return Color.white.opacity(0.5)
        }
        let maxSide = max(img.extent.width, img.extent.height)
        if maxSide > 32 {
            let scale = 32 / maxSide
            img = img.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
        }
        guard
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
    private let maxEntries = 4

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
    var bundleIdentifier: String = ""
    var showPlayerBadge: Bool = false
    var showsShadow: Bool = true

    private var resolvedBundleID: String {
        if !bundleIdentifier.isEmpty { return bundleIdentifier }
        if let pipe = trackKey.firstIndex(of: "|") {
            let prefix = String(trackKey[..<pipe])
            if !prefix.isEmpty { return prefix }
        }
        return ""
    }

    private var badgeSize: CGFloat {
        max(12, min(20, size * 0.34))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkCrossfade(
                artwork: artwork,
                unavailable: unavailable,
                trackKey: trackKey,
                size: size,
                cornerRadius: cornerRadius,
                showsShadow: showsShadow
            )

            if showPlayerBadge {
                PlayerAppBadge(
                    bundleIdentifier: resolvedBundleID,
                    size: badgeSize
                )
                .offset(x: badgeSize * 0.2, y: badgeSize * 0.2)
                .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .applyMatchedGeometry(id: "artwork", in: namespace)
    }
}

private struct ArtworkCrossfade: View {
    @EnvironmentObject private var vm: NotchViewModel
    let artwork: Data?
    let unavailable: Bool
    let trackKey: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let showsShadow: Bool

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
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(
                color: showsShadow
                    ? vm.accentColor.opacity(0.28 + pop * 0.22) : .clear,
                radius: 8 + pop * 8,
                y: 3
            )
            .shadow(
                color: showsShadow ? .black.opacity(0.45) : .clear,
                radius: 6,
                y: 3
            )
            .scaleEffect(1 + pop * 0.045)
            .opacity(loadingNewArt ? 0.82 : 1)
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

private enum PlayerAppIconStore {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleIdentifier id: String) -> NSImage? {
        guard !id.isEmpty else { return nil }
        if let cached = cache[id] { return cached }

        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == id
        }), let icon = running.icon {
            cache[id] = icon
            return icon
        }

        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: id
        ) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            cache[id] = icon
            return icon
        }

        let urls =
            LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?
            .takeRetainedValue() as? [URL]
        if let path = urls?.first?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache[id] = icon
            return icon
        }

        return nil
    }
}

private struct PlayerAppBadge: View {
    let bundleIdentifier: String
    let size: CGFloat

    @State private var icon: NSImage?

    private var cornerRadius: CGFloat { size * 0.28 }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .onAppear(perform: loadIcon)
        .onChange(of: bundleIdentifier) { _, _ in loadIcon() }
        .task(id: bundleIdentifier) {
            if icon == nil {
                try? await Task.sleep(for: .milliseconds(250))
                loadIcon()
            }
        }
    }

    private func loadIcon() {
        icon = PlayerAppIconStore.icon(forBundleIdentifier: bundleIdentifier)
    }
}
