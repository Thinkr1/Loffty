//
//  ExpandedPage.swift
//  Loffty
//
//  Created by Pierre-Louis ML on 23/08/2026.
//

import CoreGraphics
import Foundation

enum WeatherSlide: Int, CaseIterable {
    case overview
    case charts
    case forecast

    func neighbor(direction: Int) -> WeatherSlide? {
        WeatherSlide(rawValue: rawValue + (direction > 0 ? 1 : -1))
    }
}

enum ExpandedPage: String, CaseIterable, Identifiable {
    case music
    case weather

    var id: String { rawValue }

    static let storageKey = "expandedNotchPage"

    var next: ExpandedPage? {
        switch self {
        case .music: .weather
        case .weather: nil
        }
    }

    var previous: ExpandedPage? {
        switch self {
        case .music: nil
        case .weather: .music
        }
    }

    func neighbor(direction: Int) -> ExpandedPage? {
        if direction > 0 { return next }
        if direction < 0 { return previous }
        return nil
    }

    static func stored(in defaults: UserDefaults = .standard) -> ExpandedPage {
        guard let raw = defaults.string(forKey: storageKey),
            let page = ExpandedPage(rawValue: raw)
        else { return .music }
        return page
    }
}

struct HorizontalSwipeRecognizer {
    var translation = CGSize.zero
    var isTracking = false
    var distanceThreshold: CGFloat = 58
    var axisRatio: CGFloat = 1.35
    private(set) var didCommit = false

    enum Stream {
        case began(dx: CGFloat, dy: CGFloat)
        case changed(dx: CGFloat, dy: CGFloat)
        case ended
        case cancelled
        case tick(dx: CGFloat, dy: CGFloat)
    }

    mutating func handle(_ event: Stream) -> Int? {
        switch event {
        case .began(let dx, let dy):
            begin()
            move(dx: dx, dy: dy)
            return nil
        case .changed(let dx, let dy):
            move(dx: dx, dy: dy)
            return nil
        case .ended:
            return finish()
        case .cancelled:
            reset()
            return nil
        case .tick(let dx, let dy):
            guard !didCommit else { return nil }
            guard abs(dx) >= abs(dy), abs(dx) >= 6 else { return nil }
            reset()
            didCommit = true
            return dx < 0 ? 1 : -1
        }
    }

    mutating func commitIfReady() -> Int? {
        guard isTracking,
            abs(translation.width) >= distanceThreshold,
            abs(translation.width) >= abs(translation.height) * axisRatio
        else { return nil }
        let direction = translation.width < 0 ? 1 : -1
        reset()
        didCommit = true
        return direction
    }

    mutating func begin() {
        translation = .zero
        isTracking = true
        didCommit = false
    }

    mutating func move(dx: CGFloat, dy: CGFloat) {
        if !isTracking { begin() }
        translation.width += dx
        translation.height += dy
    }

    mutating func finish() -> Int? {
        defer {
            translation = .zero
            isTracking = false
        }
        guard isTracking else { return nil }
        let x = translation.width
        let y = translation.height
        guard abs(x) >= distanceThreshold,
            abs(x) >= abs(y) * axisRatio
        else { return nil }
        didCommit = true
        return x < 0 ? 1 : -1
    }

    mutating func reset() {
        translation = .zero
        isTracking = false
        didCommit = false
    }
}

struct VerticalSwipeRecognizer {
    var translation: CGFloat = 0
    var isTracking = false
    var distanceThreshold: CGFloat = 72
    var axisRatio: CGFloat = 1.25
    private(set) var didCommit = false

    mutating func handle(
        _ event: HorizontalSwipeRecognizer.Stream
    ) -> Int? {
        switch event {
        case .began(_, let dy):
            translation = 0
            isTracking = true
            didCommit = false
            translation += dy
        case .changed(_, let dy):
            if !isTracking { isTracking = true }
            translation += dy
        case .ended:
            defer {
                translation = 0
                isTracking = false
            }
            guard isTracking, abs(translation) >= distanceThreshold else {
                return nil
            }
            didCommit = true
            return translation < 0 ? 1 : -1
        case .cancelled:
            translation = 0
            isTracking = false
            didCommit = false
        case .tick(_, let dy):
            guard !didCommit else { return nil }
            guard abs(dy) >= 8 else { return nil }
            didCommit = true
            return dy < 0 ? 1 : -1
        }
        return nil
    }

    mutating func commitIfReady() -> Int? {
        guard isTracking, abs(translation) >= distanceThreshold else {
            return nil
        }
        let direction = translation < 0 ? 1 : -1
        translation = 0
        isTracking = false
        didCommit = true
        return direction
    }
}
