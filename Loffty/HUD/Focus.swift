//
//  Focus.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 16/07/2026.
//

import AppKit
import Foundation

@MainActor
final class FocusFilterBridge {
    static let shared = FocusFilterBridge()

    var onChange: ((Bool, String?) -> Void)?
    private(set) var isFocused = false
    private(set) var modeName: String?
    private var ignoreLogActivateUntil = Date.distantPast

    func handle(
        active: Bool,
        name: String? = nil,
        source: Source = .notification,
        forceAnnounce: Bool = false
    ) {
        if source == .log, active, Date() < ignoreLogActivateUntil {
            return
        }

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableName = (trimmed?.isEmpty == false) ? trimmed : nil

        let nameChanged = usableName != nil && usableName != modeName
        let activeChanged = active != isFocused

        if !active {
            ignoreLogActivateUntil = Date().addingTimeInterval(1.25)
        }

        isFocused = active
        if active {
            if let usableName { modeName = usableName }
        } else {
            modeName = nil
        }

        guard forceAnnounce || activeChanged || (active && nameChanged) else {
            return
        }
        onChange?(active, modeName)
    }

    enum Source {
        case notification
        case log
    }
}

final class FocusHUDWatcher {
    var onChange: ((Bool, String?) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var logStream: FocusLogStream?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        FocusFilterBridge.shared.onChange = { [weak self] active, name in
            self?.onChange?(active, name)
        }

        let center = DistributedNotificationCenter.default()

        observers.append(
            center.addObserver(
                forName: Notification.Name(
                    "_NSDoNotDisturbEnabledNotification"
                ),
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.announce(active: true, note: note)
            }
        )
        observers.append(
            center.addObserver(
                forName: Notification.Name(
                    "_NSDoNotDisturbDisabledNotification"
                ),
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.announce(active: false, note: note)
            }
        )

        for name in [
            "com.apple.controlcenter.focusmodes",
            "com.apple.DoNotDisturb.Mode.Changed",
            "com.apple.donotdisturb.state.changed",
        ] {
            observers.append(
                center.addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.handleAmbiguous(note)
                }
            )
        }

        let stream = FocusLogStream()
        stream.onUpdate = { event in
            Task { @MainActor in
                switch event {
                case .cleared:
                    FocusFilterBridge.shared.handle(
                        active: false,
                        source: .log,
                        forceAnnounce: true
                    )
                case .active(let identifier, let name):
                    FocusFilterBridge.shared.handle(
                        active: true,
                        name: FocusHUDWatcher.displayName(
                            identifier: identifier,
                            name: name
                        ),
                        source: .log,
                        forceAnnounce: !FocusFilterBridge.shared.isFocused
                    )
                }
            }
        }
        stream.start()
        logStream = stream
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for obs in observers {
            center.removeObserver(obs)
        }
        observers.removeAll()
        logStream?.stop()
        logStream = nil
        FocusFilterBridge.shared.onChange = nil
        started = false
    }

    private func announce(active: Bool, note: Notification) {
        FocusFilterBridge.shared.handle(
            active: active,
            name: name(from: note),
            source: .notification,
            forceAnnounce: true
        )
    }

    private func handleAmbiguous(_ note: Notification) {
        if let flag = boolValue(
            note.userInfo,
            keys: ["enabled", "active", "isActive", "focusActive", "state"]
        ) {
            announce(active: flag, note: note)
            return
        }

        let next = !FocusFilterBridge.shared.isFocused
        announce(active: next, note: note)
    }

    private func name(from note: Notification) -> String? {
        Self.displayName(
            identifier: Self.stringValue(
                note.userInfo,
                keys: [
                    "focusModeIdentifier", "identifier", "modeIdentifier",
                    "FocusModeIdentifier", "semanticModeIdentifier",
                ]
            ),
            name: Self.stringValue(
                note.userInfo,
                keys: [
                    "focusModeName", "name", "modeName", "FocusModeName",
                    "localizedName",
                ]
            )
        )
    }

    private func boolValue(_ info: [AnyHashable: Any]?, keys: [String]) -> Bool?
    {
        guard let info else { return nil }
        for key in keys {
            if let value = info[key] as? Bool { return value }
            if let value = info[key] as? NSNumber { return value.boolValue }
            if let value = info[key] as? String {
                let lower = value.lowercased()
                if ["1", "true", "yes", "on"].contains(lower) { return true }
                if ["0", "false", "no", "off"].contains(lower) { return false }
            }
        }
        return nil
    }

    private static func stringValue(_ info: [AnyHashable: Any]?, keys: [String])
        -> String?
    {
        guard let info else { return nil }
        for key in keys {
            if let value = info[key] as? String, !value.isEmpty { return value }
            if let value = info[key] as? NSString {
                let s = value as String
                if !s.isEmpty { return s }
            }
        }
        return nil
    }

    static func displayName(identifier: String?, name: String?) -> String? {
        if let name, !name.isEmpty, !name.contains(".") { return name }
        guard let identifier else { return name }
        let id = identifier.lowercased()
        if id.contains("work") { return "Work" }
        if id.contains("personal") { return "Personal" }
        if id.contains("sleep") { return "Sleep" }
        if id.contains("driving") { return "Driving" }
        if id.contains("fitness") { return "Fitness" }
        if id.contains("gaming") { return "Gaming" }
        if id.contains("mindfulness") { return "Mindfulness" }
        if id.contains("reading") { return "Reading" }
        if id.contains("reduce-interruptions")
            || id.contains("reduceinterruptions")
        {
            return "Focus"
        }
        if id.contains("donotdisturb") || id.hasSuffix(".default") {
            return "Do Not Disturb"
        }
        return name ?? "Focus"
    }
}

enum FocusLogEvent {
    case cleared
    case active(identifier: String?, name: String?)
}

final class FocusLogStream {
    var onUpdate: ((FocusLogEvent) -> Void)?

    private let queue = DispatchQueue(
        label: "Loffty.focus.logstream",
        qos: .utility
    )
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var isRunning = false
    private var restartCount = 0

    func start() {
        queue.async { [weak self] in self?.startProcess() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.cleanup(terminate: true)
            self?.restartCount = 0
        }
    }

    private func startProcess() {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--no-backtrace",
            "--style", "compact",
            "--level", "info",
            "--predicate",
            "process == \"duetexpertd\" AND (eventMessage CONTAINS \"semanticModeIdentifier\" OR eventMessage CONTAINS \"active mode assertion\" OR eventMessage CONTAINS \"activeModeIdentifier\" OR eventMessage CONTAINS \"starting:\")",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                self?.queue.async { self?.handlePipeEOF() }
                return
            }
            self?.queue.async { self?.handleIncomingData(data) }
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.handlePipeEOF() }
        }

        do {
            try process.run()
            self.process = process
            self.pipe = pipe
            self.isRunning = true
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func handlePipeEOF() {
        let wasRunning = isRunning
        cleanup(terminate: false)
        guard wasRunning, restartCount < 5 else { return }
        restartCount += 1
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startProcess()
        }
    }

    private func cleanup(terminate: Bool = false) {
        if terminate, let process, process.isRunning {
            process.terminate()
        }
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        process = nil
        buffer.removeAll(keepingCapacity: false)
        isRunning = false
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)
        let newline: UInt8 = 0x0A
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer[..<idx]
            buffer.removeSubrange(...idx)
            guard
                let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty,
                !line.hasPrefix("Filtering the log data"),
                !line.hasPrefix("Timestamp")
            else { continue }
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let lower = line.lowercased()
        if lower.contains("active mode assertion: (null)")
            || lower.contains("activemodeidentifier: (null)")
            || lower.contains("semanticmodeidentifier: (null)")
            || lower.contains("starting: 0")
            || lower.contains("cleared mode assertion")
        {
            onUpdate?(.cleared)
            return
        }

        let looksActive =
            lower.contains("active mode assertion:")
            || lower.contains("starting: 1")
            || lower.contains("asserted mode")
            || (lower.contains("semanticmodeidentifier:")
                && !lower.contains("(null)"))

        guard looksActive else { return }

        let identifier =
            extract(after: "semanticModeIdentifier:", in: line)
            ?? extract(after: "modeIdentifier:", in: line)
            ?? extract(after: "activeModeIdentifier:", in: line)
        let name = extract(after: "name:", in: line)
        guard identifier != nil || name != nil else { return }
        onUpdate?(.active(identifier: identifier, name: name))
    }

    private func extract(after key: String, in line: String) -> String? {
        guard let range = line.range(of: key, options: .caseInsensitive)
        else { return nil }
        var suffix = String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = suffix.firstIndex(where: { ";,)".contains($0) }) {
            suffix = String(suffix[..<end])
        }
        suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty || suffix == "(null)" ? nil : suffix
    }
}
