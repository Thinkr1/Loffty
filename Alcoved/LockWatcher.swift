//
//  LockWatcher.swift
//  Alcoved
//
//  Created by Pierre-Louis ML on 12/07/2026.
//

import SwiftUI
import AppKit
import CoreGraphics

final class LockWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var isLocked = false
    
    private let dnc = DistributedNotificationCenter.default()
    private var pollTimer: Timer?
    
    func start() {
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"),object: nil, queue: .main) { [weak self] _ in
            self?.setLocked(true)
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"),object: nil, queue: .main) { [weak self] _ in
            self?.setLocked(false)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,object: nil, queue: .main) { [weak self] _ in
                self?.setLocked(false)
            }
    }
    
    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        if locked { startPolling() } else { stopPolling() }
        onChange?(locked)
    }
    
    private func startPolling() {
        stopPolling()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isLocked else { return }
            if !Self.sessionScreenIsLocked() {
                self.setLocked(false)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private static func sessionScreenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
