//
//  NotchMetricsTests.swift
//  LofftyTests
//

import CoreGraphics
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

    @Test func collapsedSize() {
        let m = base()
        #expect(m.height == 32)
        #expect(m.width == 200 + 2 * m.topRadius)
        #expect(m.topRadius == 10)
    }

    @Test func expandedPlaying() {
        let m = base(expanded: true, showAlbum: true)
        #expect(m.height == 180)
        #expect(m.width == 380)
        #expect(m.topRadius == 20)
    }

    @Test func expandedIdle() {
        let m = base(expanded: true, idle: true)
        #expect(m.height == 32)
        #expect(m.topRadius == 10)
        #expect(m.width == 200 + 2 * m.side + 2 * m.topRadius)
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
        #expect(expanded.height == 170)
        #expect(expanded.bottomRadius == 30)
    }

    @Test func hudBottomRadius() {
        let m = base(hudActive: true)
        #expect(m.bottomRadius == 26)
        #expect(m.topRadius == 16)
    }
}
