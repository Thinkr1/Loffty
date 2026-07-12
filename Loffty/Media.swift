//
//  Media.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 10/07/2026.
//

// INSTALL ungive/media-control (homebrew)

import SwiftUI

final class NowPlayingStream {
    var onUpdate: ((NowPlaying) -> Void)?
    private var process: Process?
    private var current = NowPlaying()
    private var buf = Data()
    private let pth = "/opt/homebrew/bin/media-control"
    func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pth)
        p.arguments = ["stream"]
        let pipe = Pipe()
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            self.buf.append(data)
            while let nl = self.buf.firstIndex(of: 0x0A) {
                let line = self.buf[self.buf.startIndex ..< nl]
                self.buf.removeSubrange(self.buf.startIndex ... nl)
                guard !line.isEmpty,
                      let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                self.ingest(obj)
            }
        }
        try? p.run()
        process = p
    }

    private func ingest(_ obj: [String: Any]) {
        let info = (obj["payload"] as? [String: Any]) ?? obj
        if let t = info["title"] as? String { current.title = t }
        if let a = info["artist"] as? String { current.artist = a }
        if let al = info["album"] as? String { current.album = al }
        if let pl = info["playing"] as? Bool { current.isPlaying = pl }
        if let e = info["elapsedTime"] as? NSNumber { current.elapsed = e.doubleValue }
        if let d = info["duration"] as? NSNumber { current.duration = d.doubleValue }
        if let b64 = info["artworkData"] as? String { current.artwork = Data(base64Encoded: b64) }
        onUpdate?(current)
    }

    func stop() { process?.terminate() }
}

final class MediaCommands {
    private typealias SendCmd = @convention(c) (Int, [String: Any]?) -> Bool
    private typealias SetTime = @convention(c) (Double) -> Void
    private let send: SendCmd?
    private let setTime: SetTime?

    init() {
        let pth = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: pth)),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { send = nil; setTime = nil; return }
        send = unsafeBitCast(ptr, to: SendCmd.self)
        if let tptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            setTime = unsafeBitCast(tptr, to: SetTime.self)
        } else { setTime = nil }
    }

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, next = 4, prev = 5
    }

    @discardableResult
    func perform(_ c: Command) -> Bool { send?(c.rawValue, nil) ?? false }
    func setElapsed(_ t: Double) { setTime?(t) }
}

final class MediaController {
    var onUpdate: ((NowPlaying) -> Void)?
    private let reader = NowPlayingStream()
    private let commands = MediaCommands()

    func start() {
        reader.onUpdate = { [weak self] in self?.onUpdate?($0) }
        reader.start()
    }

    func command(_ c: MediaCommands.Command) { commands.perform(c) }
    func setElapsed(_ t: Double) { commands.setElapsed(t) }
}
