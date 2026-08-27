//
//  LockAccessoriesLayoutMock.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 25/08/2026.
//

import AppKit
import Darwin
import SwiftUI

struct LockAccessoriesLayoutMock: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var dragMode: DragMode = .idle
    @State private var dragTranslation: CGSize = .zero
    @State private var verticalDragStartTop: CGFloat?
    @State private var previewStripTop: CGFloat?
    @State private var chipFrames: [LockScreenAccessory: CGRect] = [:]
    @State private var wallpaper: NSImage?

    private let mockHeight: CGFloat = 320
    private let stripHeight: CGFloat = 36
    private let clockBottom: CGFloat = 84

    private enum DragMode: Equatable {
        case idle
        case vertical
        case reorder(LockScreenAccessory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Drag chips sideways to reorder. Drag the ≡ handle to move the row."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .top) {
                    background
                    chrome
                    accessoryStrip
                        .frame(maxWidth: .infinity)
                        .padding(.top, displayedStripTop)
                }
                .frame(width: width, height: mockHeight)
                .coordinateSpace(name: "lockAccessoryMock")
                .clipShape(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .onPreferenceChange(LockAccessoryChipFrameKey.self) {
                    chipFrames = $0
                }
            }
            .frame(height: mockHeight)
            .onAppear(perform: loadWallpaper)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                loadWallpaper()
            }
        }
    }

    private var settingsStripTop: CGFloat {
        let fraction = LockAccessoriesMetrics.clampedTopInsetFraction(
            settings.lockScreenAccessoriesTopInsetFraction
        )
        return clampedStripTop(mockHeight * fraction)
    }

    private var displayedStripTop: CGFloat {
        previewStripTop ?? settingsStripTop
    }

    private func clampedStripTop(_ raw: CGFloat) -> CGFloat {
        let maxTop = max(clockBottom, mockHeight - stripHeight - 16)
        return min(max(raw, clockBottom), maxTop)
    }

    private var background: some View {
        ZStack {
            fallbackBackground
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            LinearGradient(
                colors: [
                    .black.opacity(0.18),
                    .black.opacity(0.08),
                    .black.opacity(0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.22, green: 0.28, blue: 0.24),
                Color(red: 0.12, green: 0.14, blue: 0.13),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadWallpaper() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        wallpaper = LockMockWallpaper.image(for: screen)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.black.opacity(0.85))
                .frame(width: 48, height: 9)
                .padding(.top, 7)

            Text(Self.sampleDate)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)

            Text("9:41")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var accessoryStrip: some View {
        HStack(spacing: 10) {
            verticalHandle

            ForEach(settings.lockScreenAccessoryOrder) { accessory in
                chip(accessory)
                    .opacity(chipOpacity(accessory))
                    .offset(chipOffset(accessory))
                    .zIndex(dragMode == .reorder(accessory) ? 10 : 0)
                    .background(chipFrameReader(accessory))
                    .highPriorityGesture(chipGesture(for: accessory))
            }
        }
        .padding(.horizontal, 4)
        .transaction { transaction in
            if dragMode != .idle {
                transaction.animation = nil
            }
        }
    }

    private var verticalHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 22, height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.12))
            )
            .contentShape(Capsule())
            .help("Drag to move the row")
            .highPriorityGesture(handleGesture)
            .opacity(dragMode == .vertical ? 0.85 : 1)
    }

    private var handleGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragMode == .idle {
                    dragMode = .vertical
                    verticalDragStartTop = displayedStripTop
                }
                guard dragMode == .vertical,
                    let start = verticalDragStartTop
                else { return }
                previewStripTop = clampedStripTop(
                    start + value.translation.height
                )
            }
            .onEnded { _ in
                commitVerticalPreview()
                endDrag()
            }
    }

    private func chip(_ accessory: LockScreenAccessory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: accessory.mockSymbol)
                .font(.system(size: 12, weight: .semibold))
            Text(accessory.mockLabel)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(accessory.title)
    }

    private func chipOpacity(_ accessory: LockScreenAccessory) -> Double {
        if dragMode == .reorder(accessory) { return 0.9 }
        return settings.isLockScreenAccessoryEnabled(accessory) ? 1 : 0.38
    }

    private func chipOffset(_ accessory: LockScreenAccessory) -> CGSize {
        guard dragMode == .reorder(accessory) else { return .zero }
        return dragTranslation
    }

    private func chipFrameReader(_ accessory: LockScreenAccessory) -> some View
    {
        GeometryReader { geo in
            Color.clear.preference(
                key: LockAccessoryChipFrameKey.self,
                value: [
                    accessory: geo.frame(in: .named("lockAccessoryMock"))
                ]
            )
        }
    }

    private func chipGesture(for accessory: LockScreenAccessory) -> some Gesture
    {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named("lockAccessoryMock")
        )
        .onChanged { value in
            if dragMode == .idle {
                dragMode = .reorder(accessory)
            }
            guard dragMode == .reorder(accessory) else { return }
            dragTranslation = value.translation
            reorderIfNeeded(dragging: accessory, fingerX: value.location.x)
        }
        .onEnded { _ in
            endDrag()
        }
    }

    private func commitVerticalPreview() {
        guard let preview = previewStripTop else { return }
        let fraction = preview / mockHeight
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            settings.lockScreenAccessoriesTopInsetFraction =
                LockAccessoriesMetrics.clampedTopInsetFraction(fraction)
        }
    }

    private func reorderIfNeeded(
        dragging: LockScreenAccessory,
        fingerX: CGFloat
    ) {
        let ordered = settings.lockScreenAccessoryOrder
        guard ordered.firstIndex(of: dragging) != nil else { return }

        let centers: [(LockScreenAccessory, CGFloat)] = ordered.compactMap {
            accessory in
            guard let frame = chipFrames[accessory] else { return nil }
            return (accessory, frame.midX)
        }
        guard !centers.isEmpty else { return }

        let target =
            centers.min(by: { abs($0.1 - fingerX) < abs($1.1 - fingerX) })?
            .0
        guard let target,
            let to = ordered.firstIndex(of: target),
            ordered.firstIndex(of: dragging) != to
        else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            settings.moveLockScreenAccessory(dragging, to: to)
        }
    }

    private func endDrag() {
        dragMode = .idle
        dragTranslation = .zero
        verticalDragStartTop = nil
        previewStripTop = nil
    }

    private static var sampleDate: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: Date())
    }
}

private struct LockAccessoryChipFrameKey: PreferenceKey {
    static var defaultValue: [LockScreenAccessory: CGRect] = [:]

    static func reduce(
        value: inout [LockScreenAccessory: CGRect],
        nextValue: () -> [LockScreenAccessory: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension LockScreenAccessory {
    fileprivate var mockSymbol: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .bluetooth: "airpodspro"
        case .battery: "battery.100"
        case .focus: "moon.fill"
        }
    }

    fileprivate var mockLabel: String {
        switch self {
        case .weather: "25°"
        case .bluetooth: "AirPods"
        case .battery: "80%"
        case .focus: "Focus"
        }
    }
}

private enum LockMockWallpaper {
    static func image(for screen: NSScreen?) -> NSImage? {
        if let captured = captureDesktopWindow(matching: screen) {
            return captured
        }
        if let url = indexDesktopImageURL(),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        if let screen,
            let url = NSWorkspace.shared.desktopImageURL(for: screen),
            !isFallbackSystemDesktop(url),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }

    private static func isFallbackSystemDesktop(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/DefaultDesktop.")
            || path.contains("/.wallpapers/")
            || path.localizedCaseInsensitiveContains("screensaver")
    }

    private static func captureDesktopWindow(matching screen: NSScreen?)
        -> NSImage?
    {
        guard
            let createImage = cgWindowListCreateImage,
            let info = CGWindowListCopyWindowInfo(
                .optionAll,
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        let targetName = currentSpaceUUID().map { "Wallpaper-\($0)" }
        let screenFrame = screen?.frame ?? NSScreen.main?.frame

        var ranked: [(score: Int, windowID: CGWindowID)] = []
        for window in info {
            let name = window[kCGWindowName as String] as? String ?? ""
            guard name.hasPrefix("Wallpaper-"),
                let windowID = window[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            var score = 100
            if let targetName, name == targetName {
                score = 0
            } else if let screenFrame,
                let bounds = window[kCGWindowBounds as String]
                    as? [String: CGFloat]
            {
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0
                score =
                    Int(
                        abs(width - screenFrame.width)
                            + abs(height - screenFrame.height)
                    ) + 10
            }
            ranked.append((score, windowID))
        }
        ranked.sort { $0.score < $1.score }
        guard let best = ranked.first else { return nil }

        let options = CGWindowImageOption(arrayLiteral: .bestResolution)
        guard
            let unmanaged = createImage(
                .null,
                .optionIncludingWindow,
                best.windowID,
                options
            )
        else { return nil }
        let cgImage = unmanaged.takeRetainedValue()

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static func currentSpaceUUID() -> String? {
        let url = URL(
            fileURLWithPath: NSHomeDirectory()
                + "/Library/Preferences/com.apple.spaces.plist"
        )
        guard
            let root = NSDictionary(contentsOf: url) as? [String: Any],
            let config = root["SpacesDisplayConfiguration"] as? [String: Any],
            let management = config["Management Data"] as? [String: Any],
            let monitors = management["Monitors"] as? [[String: Any]]
        else { return nil }

        let preferred =
            monitors.first(where: {
                ($0["Display Identifier"] as? String) == "Main"
            }) ?? monitors.first
        let current = preferred?["Current Space"] as? [String: Any]
        return current?["uuid"] as? String
    }

    private static func indexDesktopImageURL() -> URL? {
        let store = URL(
            fileURLWithPath: NSHomeDirectory()
                + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        )
        guard
            let root = NSDictionary(contentsOf: store) as? [String: Any]
        else { return nil }

        let spaceID = currentSpaceUUID()
        let desktopNodes: [[String: Any]] = {
            var nodes: [[String: Any]] = []
            if let spaceID,
                let spaces = root["Spaces"] as? [String: Any],
                let space = spaces[spaceID] as? [String: Any]
            {
                if let displays = space["Displays"] as? [String: Any] {
                    for display in displays.values {
                        if let display = display as? [String: Any],
                            let desktop = display["Desktop"] as? [String: Any]
                        {
                            nodes.append(desktop)
                        }
                    }
                }
                if let fallback = space["Default"] as? [String: Any],
                    let desktop = fallback["Desktop"] as? [String: Any]
                {
                    nodes.append(desktop)
                }
            }
            if let displays = root["Displays"] as? [String: Any] {
                for display in displays.values {
                    if let display = display as? [String: Any],
                        let desktop = display["Desktop"] as? [String: Any]
                    {
                        nodes.append(desktop)
                    }
                }
            }
            if let system = root["SystemDefault"] as? [String: Any],
                let desktop = system["Desktop"] as? [String: Any]
            {
                nodes.append(desktop)
            }
            return nodes
        }()

        for desktop in desktopNodes {
            if let url = imageURL(fromDesktop: desktop) { return url }
        }
        return nil
    }

    private static func imageURL(fromDesktop desktop: [String: Any]) -> URL? {
        guard
            let content = desktop["Content"] as? [String: Any],
            let choices = content["Choices"] as? [[String: Any]],
            let choice = choices.first
        else { return nil }

        let provider = choice["Provider"] as? String ?? ""
        if provider.contains("screen-saver") { return nil }

        if let files = choice["Files"] as? [Any] {
            for file in files {
                if let path = file as? String {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                } else if let data = file as? Data {
                    var isStale = false
                    if let url = try? URL(
                        resolvingBookmarkData: data,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ),
                        FileManager.default.fileExists(atPath: url.path)
                    {
                        return url
                    }
                }
            }
        }

        let configuration: [String: Any]? = {
            if let data = choice["Configuration"] as? Data,
                let object = try? PropertyListSerialization
                    .propertyList(from: data, format: nil)
                    as? [String: Any]
            {
                return object
            }
            return choice["Configuration"] as? [String: Any]
        }()

        if let assetID = configuration?["assetID"] as? String
            ?? (configuration?["identifier"] as? String),
            provider.contains("aerial")
        {
            let thumb = URL(
                fileURLWithPath: NSHomeDirectory()
                    + "/Library/Application Support/com.apple.wallpaper/aerials/thumbnails/\(assetID).png"
            )
            if FileManager.default.fileExists(atPath: thumb.path) {
                return thumb
            }
        }
        return nil
    }

    private typealias CGWindowListCreateImageFn =
        @convention(c) (
            CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption
        ) -> Unmanaged<CGImage>?

    private static let cgWindowListCreateImage: CGWindowListCreateImageFn? = {
        guard
            let symbol = dlsym(
                UnsafeMutableRawPointer(bitPattern: -2),
                "CGWindowListCreateImage"
            )
        else { return nil }
        return unsafeBitCast(symbol, to: CGWindowListCreateImageFn.self)
    }()
}
