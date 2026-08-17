//
//  NotificationWatcher.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 13/08/2026.
//

import AppKit
import ApplicationServices
import SQLite3

final class NotificationBannerWatcher {
    var onBanner: ((NotchNotification) -> Void)?

    private var axObservers: [pid_t: AXObserver] = [:]
    private var pollTask: Task<Void, Never>?
    private var dbTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var seen = Set<String>()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        attachToRunningApps()
        observeWorkspace()
        startPolling()
        startDatabaseWatch()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        dbTask?.cancel()
        dbTask = nil
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        axObservers.removeAll()
        started = false
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let handler: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.attachToRunningApps()
            }
        }
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scanBanners()
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }

    private func startDatabaseWatch() {
        dbTask?.cancel()
        dbTask = Task.detached { [weak self] in
            guard let self else { return }
            var lastID = NotificationDatabaseReader.maxRecordID()
            var lastChange = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let stamp = NotificationDatabaseReader.modificationDate()
                guard let stamp, stamp > lastChange else { continue }
                lastChange = stamp
                let records = NotificationDatabaseReader.records(
                    after: lastID
                )
                for record in records {
                    lastID = max(lastID, record.recID)
                    if let note = record.notification {
                        await MainActor.run {
                            self.emit(note)
                        }
                    }
                }
            }
        }
    }

    private func attachToRunningApps() {
        let pids = watchedApplications().map(\.processIdentifier)
        for pid in axObservers.keys where !pids.contains(pid) {
            axObservers.removeValue(forKey: pid)
        }
        for app in watchedApplications() {
            installObserver(for: app)
        }
    }

    private func watchedApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            if NotificationBannerParser.isNotificationHost(bundleID: id) {
                return true
            }
            return NotificationBannerParser.app(fromBundleID: id) != nil
        }
    }

    private func installObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard axObservers[pid] == nil, pid > 0 else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            { _, _, _, refcon in
                guard let refcon else { return }
                let watcher = Unmanaged<NotificationBannerWatcher>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                Task { @MainActor in
                    watcher.scanBanners()
                }
            },
            &observer
        )
        guard result == .success, let observer else { return }
        let axApp = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [
            kAXWindowCreatedNotification,
            kAXCreatedNotification,
            kAXTitleChangedNotification,
        ] {
            AXObserverAddNotification(
                observer,
                axApp,
                name as CFString,
                refcon
            )
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        axObservers[pid] = observer
    }

    private func scanBanners() {
        for app in watchedApplications() {
            inspect(app)
        }
    }

    private func inspect(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard
            let windows = AXCopy.elements(axApp, kAXWindowsAttribute)
        else { return }
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""
        let screenOwners = onScreenBannerOwners()
        for window in windows {
            guard isBannerWindow(window, bundleID: bundleID) else { continue }
            let title = AXCopy.string(window, kAXTitleAttribute)
            let description =
                AXCopy.string(window, kAXDescriptionAttribute)
                ?? AXCopy.string(window, kAXHelpAttribute)
            let attributed = AXCopy.attributedString(
                window,
                "AXAttributedDescription"
            )
            let texts = collectText(from: window, depth: 0)
            let hints = ([appName, title, description, attributed] + texts)
                .compactMap { $0 }
            let owner = inferredOwner(
                hostBundleID: bundleID,
                hostName: appName,
                hints: hints,
                screenOwners: screenOwners
            )
            let parsed =
                NotificationBannerParser.parse(
                    title: title ?? texts.first,
                    subtitle: description,
                    body: attributed
                        ?? texts.dropFirst().joined(separator: "\n"),
                    bundleID: owner.bundleID,
                    appName: owner.appName,
                    hints: hints
                )
                ?? NotificationBannerParser.parse(
                    title: texts.first,
                    subtitle: nil,
                    body: texts.dropFirst().joined(separator: "\n"),
                    bundleID: owner.bundleID,
                    appName: owner.appName,
                    hints: hints
                )
            if let parsed {
                emit(parsed)
            } else if NotificationBannerParser.isNotificationHost(
                bundleID: bundleID
            ),
                let recent = NotificationDatabaseReader.latestWatched(
                    since: Date().addingTimeInterval(-5)
                )
            {
                emit(recent)
            }
        }
    }

    private func inferredOwner(
        hostBundleID: String,
        hostName: String,
        hints: [String],
        screenOwners: [(bundleID: String, name: String)]
    ) -> (bundleID: String, appName: String) {
        if let app = NotificationBannerParser.app(fromBundleID: hostBundleID) {
            return (
                app.primaryBundleID,
                hostName.isEmpty ? app.displayName : hostName
            )
        }
        if let app = NotificationBannerParser.resolveApp(
            bundleID: hostBundleID,
            appName: hostName,
            hints: hints
        ) {
            return (app.primaryBundleID, app.displayName)
        }
        for owner in screenOwners {
            if let app = NotificationBannerParser.app(
                fromBundleID: owner.bundleID
            )
                ?? NotificationBannerParser.app(fromName: owner.name)
            {
                return (app.primaryBundleID, owner.name)
            }
        }
        return (hostBundleID, hostName)
    }

    private func onScreenBannerOwners() -> [(bundleID: String, name: String)] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return [] }

        var owners: [(bundleID: String, name: String)] = []
        for info in list {
            guard
                let boundsDict = info[kCGWindowBounds as String]
                    as? [String: Any],
                let bounds = CGRect(
                    dictionaryRepresentation: boundsDict as CFDictionary
                )
            else { continue }
            guard isBannerBounds(bounds, quartzTopLeft: true) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            let bundleID =
                NSRunningApplication(processIdentifier: pid)?
                .bundleIdentifier ?? ""
            if NotificationBannerParser.app(fromBundleID: bundleID) != nil
                || NotificationBannerParser.app(fromName: name) != nil
            {
                owners.append((bundleID, name))
            }
        }
        return owners
    }

    private func isBannerWindow(_ window: AXUIElement, bundleID: String) -> Bool
    {
        let subrole = AXCopy.string(window, kAXSubroleAttribute) ?? ""
        let roleDesc = AXCopy.string(window, kAXRoleDescriptionAttribute) ?? ""
        let combined = (subrole + " " + roleDesc).lowercased()
        if combined.contains("banner") || combined.contains("notification") {
            return true
        }
        guard let size = AXCopy.size(window) else { return false }
        let bounds = CGRect(
            origin: AXCopy.origin(window) ?? .zero,
            size: size
        )
        if NotificationBannerParser.isNotificationHost(bundleID: bundleID) {
            return isBannerSize(size)
        }
        return isBannerBounds(bounds, quartzTopLeft: false)
    }

    private func isBannerSize(_ size: CGSize) -> Bool {
        size.width >= 180 && size.width <= 720
            && size.height >= 28 && size.height <= 240
    }

    private func isBannerBounds(_ bounds: CGRect, quartzTopLeft: Bool) -> Bool {
        guard isBannerSize(bounds.size) else { return false }
        if quartzTopLeft {
            return bounds.minY <= 160
        }
        for screen in NSScreen.screens {
            if bounds.maxY >= screen.frame.maxY - 160 { return true }
            if bounds.minY <= 160 { return true }
        }
        return false
    }

    private func collectText(from element: AXUIElement, depth: Int) -> [String]
    {
        guard depth < 8 else { return [] }
        var values: [String] = []
        var namesRef: CFArray?
        if AXUIElementCopyAttributeNames(element, &namesRef) == .success,
            let names = namesRef as? [String]
        {
            for name in names {
                if let text = AXCopy.string(element, name),
                    text.count >= 2, text.count <= 240,
                    !values.contains(text)
                {
                    values.append(text)
                }
            }
        }
        if let children = AXCopy.elements(element, kAXChildrenAttribute) {
            for child in children.prefix(20) {
                for text in collectText(from: child, depth: depth + 1)
                where !values.contains(text) {
                    values.append(text)
                }
            }
        }
        return values
    }

    private func emit(_ note: NotchNotification) {
        let key = note.fingerprint
        if seen.contains(key) { return }
        seen.insert(key)
        if seen.count > 80 {
            seen = Set(seen.suffix(40))
        }
        onBanner?(note)
    }
}

private enum AXCopy {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else { return nil }
        if let text = value as? String {
            return NotificationBannerParser.clean(text)
        }
        if let attributed = value as? NSAttributedString {
            return NotificationBannerParser.clean(attributed.string)
        }
        return nil
    }

    static func attributedString(_ element: AXUIElement, _ attribute: String)
        -> String?
    {
        string(element, attribute)
    }

    static func elements(_ element: AXUIElement, _ attribute: String)
        -> [AXUIElement]?
    {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &value
            ) == .success
        else { return nil }
        let size = value as! AXValue
        var out = CGSize.zero
        AXValueGetValue(size, .cgSize, &out)
        return out
    }

    static func origin(_ element: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &value
            ) == .success
        else { return nil }
        let point = value as! AXValue
        var out = CGPoint.zero
        AXValueGetValue(point, .cgPoint, &out)
        return out
    }
}

enum NotificationDatabaseReader: Sendable {
    struct Record: Sendable {
        let recID: Int
        let notification: NotchNotification?
    }

    nonisolated static func databaseDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Group Containers/group.com.apple.usernoted/db2"
            )
    }

    nonisolated static func canReadDatabase() -> Bool {
        FileManager.default.isReadableFile(
            atPath: databaseDirectory().appendingPathComponent("db").path
        )
    }

    nonisolated static func modificationDate() -> Date? {
        let dir = databaseDirectory()
        let wal = dir.appendingPathComponent("db-wal")
        let db = dir.appendingPathComponent("db")
        let values = [wal, db].compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        }
        return values.max()
    }

    nonisolated static func latestWatched(since date: Date)
        -> NotchNotification?
    {
        let maxID = maxRecordID()
        let start = max(maxID - 16, 0)
        return records(after: start, limit: 16, newestFirst: true)
            .compactMap(\.notification)
            .first { $0.deliveredAt >= date }
    }

    nonisolated static func maxRecordID() -> Int {
        records(after: -1, limit: 1, newestFirst: true).first?.recID ?? 0
    }

    nonisolated static func records(
        after recID: Int,
        limit: Int = 8,
        newestFirst: Bool = false
    ) -> [Record] {
        guard let copy = copyDatabase() else { return [] }
        defer { try? FileManager.default.removeItem(at: copy.folder) }

        var db: OpaquePointer?
        guard
            sqlite3_open_v2(
                copy.db.path,
                &db,
                SQLITE_OPEN_READONLY,
                nil
            ) == SQLITE_OK
        else { return [] }
        defer { sqlite3_close(db) }

        let order = newestFirst ? "DESC" : "ASC"
        let sql = """
            SELECT r.rec_id, IFNULL(a.identifier, ''), r.data, r.delivered_date
            FROM record r
            LEFT JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ?
            ORDER BY r.rec_id \(order)
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(recID))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var out: [Record] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(stmt, 0))
            let bundle =
                sqlite3_column_text(stmt, 1).map {
                    String(cString: $0)
                } ?? ""
            let blobBytes = sqlite3_column_bytes(stmt, 2)
            let blob = sqlite3_column_blob(stmt, 2).map {
                Data(bytes: $0, count: Int(blobBytes))
            }
            let delivered = sqlite3_column_double(stmt, 3)
            let date = Date(timeIntervalSinceReferenceDate: delivered)
            let note = blob.flatMap {
                NotificationBannerParser.decodeRecord(
                    data: $0,
                    bundleID: bundle,
                    deliveredAt: date,
                    recID: id
                )
            }
            out.append(Record(recID: id, notification: note))
        }
        return out
    }

    nonisolated private static func copyDatabase() -> (folder: URL, db: URL)? {
        let source = databaseDirectory()
        let db = source.appendingPathComponent("db")
        guard FileManager.default.fileExists(atPath: db.path) else {
            return nil
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("loffty-nc-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            for name in ["db", "db-wal", "db-shm"] {
                let src = source.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else {
                    continue
                }
                try FileManager.default.copyItem(
                    at: src,
                    to: folder.appendingPathComponent(name)
                )
            }
            return (folder, folder.appendingPathComponent("db"))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }
}
