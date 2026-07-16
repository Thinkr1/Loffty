//
//  AirDrop.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 17/07/2026.
//

import AppKit
import Combine
import Darwin
import Network
import ObjectiveC
import SwiftUI

enum AirDropPhase: Equatable {
    case idle
    case picking
    case sent(title: String)
    case receiving(from: String, title: String)
    case received(title: String)

    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

@MainActor
final class AirDropController: ObservableObject {
    static let shared = AirDropController()

    @Published private(set) var phase: AirDropPhase = .idle
    @Published private(set) var files: [URL] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var systemChooserPresented = false

    private var transferObserver: NSObject?
    private var transferBridge: AirDropTransferBridge?
    private var sharingBridge: AirDropSharingBridge?
    private var sharingService: NSSharingService?
    private var dismissTask: Task<Void, Never>?
    private var chooserTask: Task<Void, Never>?
    private var chooserWatchTask: Task<Void, Never>?
    private var scopedURLs: [URL] = []
    private var sharingLoaded = false
    private var localNetworkBrowser: NWBrowser?
    private var didAutoPresentChooser = false
    private var sawMeaningfulProgress = false
    private var awaitingDelivery = false

    private init() {
        sharingLoaded = Self.loadSharing()
    }

    func offer(urls: [URL]) {
        guard AppSettings.shared.airDropHUD, !urls.isEmpty else { return }
        let unique = Self.dedupe(urls)
        if unique.map(\.path) == files.map(\.path), case .picking = phase {
            return
        }

        dismissTask?.cancel()
        systemChooserPresented = false
        didAutoPresentChooser = false
        sawMeaningfulProgress = false
        awaitingDelivery = false
        releaseScopedURLs()

        for url in unique {
            _ = url.startAccessingSecurityScopedResource()
            scopedURLs.append(url)
        }

        withAnimation(NotchViewModel.airDropSpring) {
            files = unique
            phase = .picking
            progress = 0
        }
        primeLocalNetworkAccess()
        armSystemChooser()
    }

    func openSystemAirDrop() {
        guard !files.isEmpty else { return }
        let service = NSSharingService(named: .sendViaAirDrop)
        guard let service, service.canPerform(withItems: files) else { return }

        let bridge = AirDropSharingBridge(
            onShared: { [weak self] in
                Task { @MainActor in self?.handleSystemShareBegan() }
            },
            onFailedOrCancelled: { [weak self] in
                Task { @MainActor in self?.handleSystemShareDismissed() }
            }
        )
        service.delegate = bridge
        sharingBridge = bridge
        sharingService = service

        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
        withAnimation(NotchViewModel.airDropSpring) {
            systemChooserPresented = true
        }
        watchSystemChooserDismissal()
    }

    func cancel() {
        dismissTask?.cancel()
        chooserTask?.cancel()
        chooserWatchTask?.cancel()
        stopLocalNetworkPrime()
        releaseScopedURLs()
        sharingService?.delegate = nil
        sharingService = nil
        sharingBridge = nil
        withAnimation(NotchViewModel.airDropSpring) {
            phase = .idle
            files = []
            progress = 0
            systemChooserPresented = false
        }
        didAutoPresentChooser = false
        sawMeaningfulProgress = false
        awaitingDelivery = false
    }

    func startReceiveMonitoring() {
        guard sharingLoaded, transferObserver == nil else { return }
        guard
            let cls = NSClassFromString("SFAirDropTransferObserver")
                as? NSObject.Type
        else { return }
        let observer = cls.init()
        let bridge = AirDropTransferBridge(
            onTransfer: { [weak self] transfer in
                Task { @MainActor in self?.handle(transfer: transfer) }
            },
            onRemoved: { [weak self] transfer in
                Task { @MainActor in self?.handleTransferRemoved(transfer) }
            }
        )
        observer.setValue(bridge, forKey: "delegate")
        if observer.responds(to: NSSelectorFromString("setIsModern:")) {
            observer.setValue(true, forKey: "isModern")
        }
        if observer.responds(to: NSSelectorFromString("activate")) {
            observer.perform(NSSelectorFromString("activate"))
        }
        transferObserver = observer
        transferBridge = bridge
    }

    func stopReceiveMonitoring() {
        if let observer = transferObserver,
            observer.responds(to: NSSelectorFromString("invalidate"))
        {
            observer.perform(NSSelectorFromString("invalidate"))
        }
        transferObserver = nil
        transferBridge = nil
    }

    private func primeLocalNetworkAccess() {
        guard localNetworkBrowser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_airdrop._tcp", domain: nil),
            using: params
        )
        browser.stateUpdateHandler = { (_: NWBrowser.State) in }
        browser.browseResultsChangedHandler = {
            (_: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
        }
        browser.start(queue: .main)
        localNetworkBrowser = browser
    }

    private func stopLocalNetworkPrime() {
        localNetworkBrowser?.cancel()
        localNetworkBrowser = nil
    }

    private func armSystemChooser() {
        chooserTask?.cancel()
        chooserTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            guard case .picking = phase, !didAutoPresentChooser else { return }
            didAutoPresentChooser = true
            openSystemAirDrop()
        }
    }

    private func handle(transfer: NSObject) {
        let title =
            (transfer.value(forKey: "contentsTitle") as? String)
            ?? (transfer.value(forKey: "contentsDescription") as? String)
            ?? fileSummary
        let meta = transfer.value(forKey: "metaData") as? NSObject
        let peer =
            (meta?.value(forKey: "senderComputerName") as? String)
            ?? (meta?.value(forKey: "senderName") as? String)
            ?? (meta?.value(forKey: "receiverComputerName") as? String)
            ?? (meta?.value(forKey: "receiverName") as? String)
            ?? "AirDrop"
        let state = transfer.value(forKey: "transferState") as? Int ?? 0
        let prog =
            (transfer.value(forKey: "transferProgress") as? NSNumber)?
            .doubleValue ?? 0

        let isOutgoing: Bool = {
            switch phase {
            case .sent: return true
            case .receiving, .received: return false
            case .picking, .idle: return !files.isEmpty || awaitingDelivery
            }
        }()

        chooserWatchTask?.cancel()

        if [2, 3, 4].contains(state) {
            cancel()
            return
        }

        if prog > 0.12 { sawMeaningfulProgress = true }

        let succeeded = prog >= 0.99 || state >= 5
        if succeeded {
            guard sawMeaningfulProgress || prog >= 0.99 else {
                cancel()
                return
            }
            finishSuccessfully(outgoing: isOutgoing, title: title)
            return
        }

        if isOutgoing {
            dismissTask?.cancel()
            awaitingDelivery = true
            withAnimation(NotchViewModel.airDropSpring) {
                systemChooserPresented = false
            }
            return
        }

        dismissTask?.cancel()
        withAnimation(NotchViewModel.airDropSpring) {
            progress = max(0.06, min(prog > 0 ? prog : progress, 0.99))
            systemChooserPresented = false
            phase = .receiving(from: peer, title: title)
        }
    }

    private func handleTransferRemoved(_ transfer: NSObject) {
        if !sawMeaningfulProgress {
            if awaitingDelivery || phase == .picking {
                cancel()
            }
            return
        }
        if case .receiving = phase { cancel() }
    }

    private func handleSystemShareBegan() {
        chooserWatchTask?.cancel()
        if case .sent = phase { return }
        if case .received = phase { return }
        if case .receiving = phase { return }

        awaitingDelivery = true
        withAnimation(NotchViewModel.airDropSpring) {
            systemChooserPresented = false
            phase = .picking
        }
        armGhostShareTimeout()
    }

    private func handleSystemShareDismissed() {
        if sawMeaningfulProgress { return }
        cancel()
    }

    private func armGhostShareTimeout() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            guard !sawMeaningfulProgress, awaitingDelivery else { return }
            if case .picking = phase { cancel() }
        }
    }

    private func finishSuccessfully(outgoing: Bool, title: String) {
        dismissTask?.cancel()
        awaitingDelivery = false
        withAnimation(NotchViewModel.airDropSpring) {
            progress = 1
            systemChooserPresented = false
            phase = outgoing ? .sent(title: title) : .received(title: title)
        }
        scheduleDismiss(after: 0.95)
    }

    private func watchSystemChooserDismissal() {
        chooserWatchTask?.cancel()
        chooserWatchTask = Task {
            var sawUI = false
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                guard case .picking = phase else { return }
                let visible = Self.isSystemAirDropUIVisible()
                if visible {
                    sawUI = true
                } else if sawUI {
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled, case .picking = phase else {
                        return
                    }
                    cancel()
                    return
                }
            }
        }
    }

    private var fileSummary: String {
        if files.isEmpty { return "AirDrop" }
        if files.count == 1 { return files[0].lastPathComponent }
        return "\(files.count) items"
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            cancel()
        }
    }

    private func releaseScopedURLs() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }

    private static func isSystemAirDropUIVisible() -> Bool {
        let opts: CGWindowListOption = [
            .optionOnScreenOnly, .excludeDesktopElements,
        ]
        guard
            let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        for window in list {
            let name = (window[kCGWindowName as String] as? String) ?? ""
            let owner = (window[kCGWindowOwnerName as String] as? String) ?? ""
            if name.localizedCaseInsensitiveContains("AirDrop") { return true }
            if owner == "SharingUIService" {
                let bounds = window[kCGWindowBounds as String] as? [String: Any]
                let w = (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0
                let h = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
                if w > 160, h > 120 { return true }
            }
        }
        return false
    }

    private static func loadSharing() -> Bool {
        let paths = [
            "/System/Library/PrivateFrameworks/Sharing.framework/Sharing",
            "/System/Library/PrivateFrameworks/Sharing.framework/Versions/A/Sharing",
        ]
        for path in paths {
            if dlopen(path, RTLD_NOW) != nil { return true }
        }
        return NSClassFromString("SFAirDropTransferObserver") != nil
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    static func previewImage(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private final class AirDropTransferBridge: NSObject {
    let onTransfer: (NSObject) -> Void
    let onRemoved: (NSObject) -> Void

    init(
        onTransfer: @escaping (NSObject) -> Void,
        onRemoved: @escaping (NSObject) -> Void
    ) {
        self.onTransfer = onTransfer
        self.onRemoved = onRemoved
    }

    @objc func updatedTransfer(_ transfer: NSObject) {
        onTransfer(transfer)
    }
    @objc func removedTransfer(_ transfer: NSObject) {
        onRemoved(transfer)
    }
    @objc func transferObserver(
        _ observer: NSObject,
        updatedTransfer transfer: NSObject
    ) {
        onTransfer(transfer)
    }
    @objc func transferObserver(
        _ observer: NSObject,
        removedTransfer transfer: NSObject
    ) {
        onRemoved(transfer)
    }
}

private final class AirDropSharingBridge: NSObject, NSSharingServiceDelegate {
    let onShared: () -> Void
    let onFailedOrCancelled: () -> Void

    init(
        onShared: @escaping () -> Void,
        onFailedOrCancelled: @escaping () -> Void
    ) {
        self.onShared = onShared
        self.onFailedOrCancelled = onFailedOrCancelled
    }

    func sharingService(
        _ sharingService: NSSharingService,
        didShareItems items: [Any]
    ) {
        onShared()
    }

    func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: any Error
    ) {
        onFailedOrCancelled()
    }
}

struct AirDropNotchContent: View {
    @ObservedObject var airDrop: AirDropController

    var body: some View {
        Group {
            switch airDrop.phase {
            case .picking:
                pickingBody
            case .sent(let title):
                sessionBody(
                    title: title,
                    subtitle: "Delivered",
                    complete: true
                )
            case .receiving(let from, let title):
                sessionBody(
                    title: title,
                    subtitle: "From \(from)",
                    complete: false
                )
            case .received(let title):
                sessionBody(
                    title: title,
                    subtitle: "Received",
                    complete: true
                )
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 42)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchViewModel.airDropSpring, value: airDrop.phase)
        .animation(
            NotchViewModel.airDropSpring,
            value: airDrop.systemChooserPresented
        )
    }

    private var pickingBody: some View {
        HStack(spacing: 14) {
            fileThumb
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: fileSummary,
                    font: .system(size: 15, weight: .semibold),
                    color: .white,
                    height: 18
                )
                Text(
                    airDrop.systemChooserPresented
                        ? "Choose a device" : "AirDrop"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                airDrop.openSystemAirDrop()
            } label: {
                AirDropPulseBars(active: !airDrop.systemChooserPresented)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                airDrop.systemChooserPresented
                    ? "Show AirDrop again" : "Opening AirDrop"
            )
        }
    }

    private func sessionBody(
        title: String,
        subtitle: String,
        complete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                fileThumb
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: title,
                        font: .system(size: 15, weight: .semibold),
                        color: .white,
                        height: 18
                    )
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            .white.opacity(complete ? 0.55 : 0.45)
                        )
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 16)
                } else {
                    AirDropPulseBars(active: true)
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 28, height: 16)
                }
            }

            GeometryReader { geo in
                Capsule()
                    .fill(.white.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(complete ? 0.7 : 0.85))
                            .frame(
                                width: max(
                                    4,
                                    geo.size.width
                                        * (complete ? 1 : airDrop.progress)
                                )
                            )
                            .animation(
                                .easeOut(duration: 0.22),
                                value: airDrop.progress
                            )
                    }
            }
            .frame(height: 3)
        }
    }

    private var fileThumb: some View {
        Group {
            if let url = airDrop.files.first,
                let icon = AirDropController.previewImage(for: url)
            {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private var fileSummary: String {
        let files = airDrop.files
        if files.isEmpty { return "Files" }
        if files.count == 1 { return files[0].lastPathComponent }
        return "\(files.count) items"
    }
}

private struct AirDropPulseBars: View {
    var active: Bool
    private let phases: [Double] = [0.0, 0.7, 1.4, 2.1, 2.8]

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 28.0, paused: !active)
        ) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .frame(
                            width: 2.5,
                            height: active
                                ? 4 + 10
                                    * (0.45 + 0.55
                                        * abs(sin(t * 3.1 + phases[i])))
                                : CGFloat([5, 9, 12, 8, 4][i])
                        )
                        .opacity(active ? 0.85 : 0.35)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.25), value: active)
        }
    }
}
