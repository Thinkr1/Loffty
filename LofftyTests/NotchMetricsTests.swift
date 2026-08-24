//
//  NotchMetricsTests.swift
//  LofftyTests
//

import CoreGraphics
import SwiftUI
import Testing

@testable import Loffty

@Suite("NotchMetrics")
struct NotchMetricsTests {
    private func base(
        expanded: Bool = false,
        idle: Bool = false,
        hudActive: Bool = false,
        sideAnnouncement: Bool = false,
        airDrop: Bool = false,
        airDropTransfer: Bool = false,
        extended: Bool = false,
        showAlbum: Bool = false
    ) -> NotchMetrics {
        NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: expanded,
            idle: idle,
            extended: extended,
            hudActive: hudActive,
            sideAnnouncement: sideAnnouncement,
            airDrop: airDrop,
            airDropTransfer: airDropTransfer,
            showAlbum: showAlbum
        )
    }

    @Test func customizingToolbarGrowsTheNotch() {
        let playing = base(expanded: true, showAlbum: false)
        let customizing = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: true,
            idle: false,
            extended: false,
            hudActive: false,
            showAlbum: false,
            customizingToolbar: true
        )
        #expect(customizing.width == MediaToolbarCustomizeLayout.width)
        #expect(
            customizing.height
                == MediaToolbarCustomizeLayout.expandedHeight(showAlbum: false)
        )
        #expect(customizing.height > playing.height)
        #expect(customizing.width > playing.width)
    }

    @Test func collapsedSize() {
        let m = base()
        #expect(m.height == 32)
        #expect(m.width == 200 + 2 * m.topRadius)
        #expect(m.topRadius == 10)
    }

    @Test func expandedPlaying() {
        let m = base(expanded: true, showAlbum: true)
        #expect(m.height == 206)
        #expect(m.width == 392)
        #expect(m.topRadius == 22)
    }

    @Test func expandedWeatherUsesRoomForItsSlides() {
        let idleMusic = base(expanded: true, idle: true)
        let weather = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: true,
            idle: true,
            extended: false,
            hudActive: false,
            weather: true
        )
        #expect(idleMusic.height == 196)
        #expect(idleMusic.width == 392)
        #expect(weather.height == 240)
        #expect(weather.width == 392)
        #expect(weather.topRadius == 22)
        #expect(weather.bottomRadius == 30)
    }

    @Test func weatherSwipeExpansionGrowsNotchByProgress() {
        let base = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: true,
            idle: true,
            extended: false,
            hudActive: false,
            weather: true
        )
        let expanded = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: true,
            idle: true,
            extended: false,
            hudActive: false,
            weather: true,
            swipeExpansion: 0.5
        )
        #expect(base.width == 392)
        #expect(base.height == 240)
        #expect(expanded.width == 408)
        #expect(expanded.height == 252)
    }

    @Test func expandedIdle() {
        let m = base(expanded: true, idle: true)
        #expect(m.height == 196)
        #expect(m.topRadius == 22)
        #expect(m.width == 392)
    }

    @Test func hudActiveExtendsHeight() {
        let m = base(hudActive: true)
        #expect(m.height == 32 + m.hudExtra)
        #expect(m.width == 200 + 2 * m.topRadius + 36)
    }

    @Test func sideAnnouncementWiderThanCollapsed() {
        let collapsed = base()
        let side = base(sideAnnouncement: true)
        #expect(side.width > collapsed.width)
        #expect(side.side > collapsed.side)
    }

    @Test func airDropMetrics() {
        let idle = base(airDrop: true)
        #expect(idle.height == 112)
        #expect(idle.width == 380)
        let transfer = base(airDrop: true, airDropTransfer: true)
        #expect(transfer.height == 128)
        #expect(idle.bottomRadius == 24)
    }

    @Test func extendedAndExpandedWithoutAlbum() {
        let extended = base(extended: true)
        #expect(
            extended.width == 200 + 2 * extended.side + 2 * extended.topRadius
        )
        let expanded = base(expanded: true, showAlbum: false)
        #expect(expanded.height == 196)
        #expect(expanded.bottomRadius == 30)
    }

    @Test func hudBottomRadius() {
        let m = base(hudActive: true)
        #expect(m.bottomRadius == 26)
        #expect(m.topRadius == 16)
    }

    @Test func videoArtworkWidensExtendedSides() {
        let square = base(extended: true)
        let video = NotchMetrics(
            notchW: 200,
            notchH: 32,
            expanded: false,
            idle: false,
            extended: true,
            hudActive: false,
            artAspectRatio: 16 / 9
        )
        #expect(video.artWidth > square.artWidth)
        #expect(video.side > square.side)
        #expect(abs(video.artWidth - square.artSize * 16 / 9) < 0.01)
    }
}

@Suite("Notch bottom edge")
struct NotchBottomEdgeTests {
    @Test func pathRunsFromScreenTopToScreenTop() {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 32)
        let points = pathPoints(
            NotchBottomEdge.path(in: rect, topRadius: 10, bottomRadius: 12)
        )
        #expect(points.first == CGPoint(x: rect.minX, y: rect.minY))
        #expect(points.last == CGPoint(x: rect.maxX, y: rect.minY))
        #expect(points.contains { $0.y == rect.maxY })
    }

    @Test func pathFollowsTopCornersWithoutClosingAcrossTheTop() {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 32)
        let path = NotchBottomEdge.path(
            in: rect,
            topRadius: 10,
            bottomRadius: 12
        )
        let points = pathPoints(path)
        #expect(points.contains(CGPoint(x: 10, y: 10)))
        #expect(points.contains(CGPoint(x: 210, y: 10)))

        var closed = false
        path.cgPath.applyWithBlock { element in
            if element.pointee.type == .closeSubpath { closed = true }
        }
        #expect(!closed)
    }

    private func pathPoints(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.cgPath.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(pts[0])
            case .addQuadCurveToPoint:
                points.append(pts[0])
                points.append(pts[1])
            case .addCurveToPoint:
                points.append(pts[0])
                points.append(pts[1])
                points.append(pts[2])
            default:
                break
            }
        }
        return points
    }
}
