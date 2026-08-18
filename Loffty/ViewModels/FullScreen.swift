//
//  FullScreen.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 18/08/2026.
//

import AppKit
import ApplicationServices
import CoreGraphics

enum FullScreenPolicy {
    nonisolated static func shouldHideNotch(
        hideInAnyFullScreen: Bool,
        selectedBundleIDs: [String],
        frontmostBundleID: String?,
        isFullScreen: Bool
    ) -> Bool {
        guard isFullScreen, let id = frontmostBundleID, !id.isEmpty else {
            return false
        }
        if hideInAnyFullScreen { return true }
        return selectedBundleIDs.contains(id)
    }
}

enum FullScreenDetection {
    nonisolated static func shouldConsider(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        if bundleID == Bundle.main.bundleIdentifier { return false }
        return !ignoredBundleIDs.contains(bundleID)
    }

    nonisolated static func isFullScreenBounds(
        _ bounds: CGRect,
        screenQuartz: CGRect,
        layer: Int,
        slop: CGFloat = 6
    ) -> Bool {
        guard layer == 0 else { return false }
        guard bounds.width > 1, bounds.height > 1 else { return false }
        guard screenQuartz.width > 1, screenQuartz.height > 1 else {
            return false
        }
        let widthRatio = bounds.width / screenQuartz.width
        let heightRatio = bounds.height / screenQuartz.height
        guard widthRatio >= 0.97, heightRatio >= 0.97 else { return false }
        return abs(bounds.midX - screenQuartz.midX) <= slop * 8
            && abs(bounds.midY - screenQuartz.midY) <= slop * 8
    }

    nonisolated static func quartzFrame(
        screenFrame: CGRect,
        primaryFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: primaryFrame.maxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    nonisolated static func appHasFullScreenWindow(
        pid: pid_t,
        screenQuartz: CGRect
    ) -> Bool {
        if hasFullScreenSizedWindow(pid: pid, screenQuartz: screenQuartz) {
            return true
        }
        return axHasFullScreenWindow(pid: pid)
            && hasNearlyFullWindow(pid: pid, screenQuartz: screenQuartz)
    }

    nonisolated static func bundleIdentifier(at url: URL) -> String? {
        if let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty {
            return id
        }
        let info = url.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: info),
            let id = dict["CFBundleIdentifier"] as? String,
            !id.isEmpty
        {
            return id
        }
        return nil
    }

    nonisolated static func displayName(bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) {
            return FileManager.default.displayName(atPath: url.path)
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }), let name = running.localizedName, !name.isEmpty {
            return name
        }
        return bundleID
    }

    private nonisolated static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.NotificationCenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
    ]

    private nonisolated static func hasFullScreenSizedWindow(
        pid: pid_t,
        screenQuartz: CGRect
    ) -> Bool {
        windows(for: pid).contains { window in
            isFullScreenBounds(
                window.bounds,
                screenQuartz: screenQuartz,
                layer: window.layer
            )
        }
    }

    private nonisolated static func hasNearlyFullWindow(
        pid: pid_t,
        screenQuartz: CGRect
    ) -> Bool {
        windows(for: pid).contains { window in
            guard window.layer == 0 else { return false }
            let widthRatio = window.bounds.width / max(screenQuartz.width, 1)
            let heightRatio = window.bounds.height / max(screenQuartz.height, 1)
            return widthRatio >= 0.88 && heightRatio >= 0.88
                && window.bounds.intersects(screenQuartz)
        }
    }

    private nonisolated static func windows(for pid: pid_t) -> [(
        bounds: CGRect, layer: Int
    )] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return [] }

        var result: [(bounds: CGRect, layer: Int)] = []
        for info in list {
            let owner = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard owner == pid else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard
                let boundsDict = info[kCGWindowBounds as String]
                    as? [String: Any],
                let bounds = CGRect(
                    dictionaryRepresentation: boundsDict as CFDictionary
                )
            else { continue }
            result.append((bounds: bounds, layer: layer))
        }
        return result
    }

    private nonisolated static func axHasFullScreenWindow(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                app,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
            let list = windowsRef as? [AXUIElement]
        else { return false }
        return list.contains { axIsFullScreen($0) }
    }

    private nonisolated static func axIsFullScreen(_ window: AXUIElement)
        -> Bool
    {
        for name in ["AXFullScreen", "AXFullscreen"] {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(
                window,
                name as CFString,
                &value
            ) == .success,
                let flag = value as? Bool
            {
                return flag
            }
        }
        return false
    }
}

@MainActor
final class FullScreenWatcher {
    var onChange: ((Bool, String?) -> Void)?

    private(set) var isFullScreen = false
    private(set) var frontmostBundleID: String?

    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var started = false
    private var screenProvider: (() -> NSScreen?)?

    func start(screenProvider: @escaping () -> NSScreen?) {
        self.screenProvider = screenProvider
        guard !started else {
            refresh()
            return
        }
        started = true

        let workspace = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            observers.append(
                workspace.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        )

        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refresh()
    }

    func stop() {
        started = false
        screenProvider = nil
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        publish(isFullScreen: false, bundleID: nil)
    }

    func refresh() {
        guard started, let screen = screenProvider?() else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        let fullscreen: Bool
        if let pid = front?.processIdentifier,
            let bundleID,
            FullScreenDetection.shouldConsider(bundleID: bundleID)
        {
            let primary = NSScreen.screens.first?.frame ?? screen.frame
            let screenQuartz = FullScreenDetection.quartzFrame(
                screenFrame: screen.frame,
                primaryFrame: primary
            )
            fullscreen = FullScreenDetection.appHasFullScreenWindow(
                pid: pid,
                screenQuartz: screenQuartz
            )
        } else {
            fullscreen = false
        }
        publish(isFullScreen: fullscreen, bundleID: bundleID)
    }

    private func publish(isFullScreen: Bool, bundleID: String?) {
        guard
            isFullScreen != self.isFullScreen
                || bundleID != frontmostBundleID
        else { return }
        self.isFullScreen = isFullScreen
        frontmostBundleID = bundleID
        onChange?(isFullScreen, bundleID)
    }
}
