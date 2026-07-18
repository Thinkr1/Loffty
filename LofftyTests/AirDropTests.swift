//
//  AirDropTests.swift
//  LofftyTests
//

import Foundation
import Testing

@testable import Loffty

@Suite("AirDrop")
struct AirDropTests {
    @Test func phaseIsActive() {
        #expect(!AirDropPhase.idle.isActive)
        #expect(AirDropPhase.picking.isActive)
        #expect(AirDropPhase.sent(title: "a").isActive)
        #expect(AirDropPhase.receiving(from: "x", title: "y").isActive)
        #expect(AirDropPhase.received(title: "z").isActive)
    }

    @Test func dedupePreservesOrderAndUniquePaths() {
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        let a2 = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(AirDropController.dedupe([a, b, a2]) == [a, b])
    }

    @Test func fileSummary() {
        #expect(AirDropLogic.fileSummary(for: []) == "AirDrop")
        let one = URL(fileURLWithPath: "/tmp/photo.png")
        #expect(AirDropLogic.fileSummary(for: [one]) == "photo.png")
        #expect(
            AirDropLogic.fileSummary(for: [
                one, URL(fileURLWithPath: "/tmp/b.txt"),
            ]) == "2 items"
        )
    }

    @Test func isOutgoingRules() {
        #expect(
            AirDropLogic.isOutgoing(
                phase: .sent(title: "x"),
                filesNonEmpty: false,
                awaitingDelivery: false
            )
        )
        #expect(
            !AirDropLogic.isOutgoing(
                phase: .receiving(from: "a", title: "b"),
                filesNonEmpty: true,
                awaitingDelivery: true
            )
        )
        #expect(
            AirDropLogic.isOutgoing(
                phase: .picking,
                filesNonEmpty: true,
                awaitingDelivery: false
            )
        )
    }

    @Test func transferDecideCancelSucceedContinue() {
        #expect(
            AirDropLogic.decide(
                state: 3,
                progress: 0.5,
                sawMeaningfulProgress: true,
                isOutgoing: true
            ) == .cancel
        )
        #expect(
            AirDropLogic.decide(
                state: 5,
                progress: 0.2,
                sawMeaningfulProgress: true,
                isOutgoing: false
            ) == .succeed(outgoing: false)
        )
        #expect(
            AirDropLogic.decide(
                state: 0,
                progress: 0.99,
                sawMeaningfulProgress: false,
                isOutgoing: true
            ) == .succeed(outgoing: true)
        )
        #expect(
            AirDropLogic.decide(
                state: 5,
                progress: 0.2,
                sawMeaningfulProgress: false,
                isOutgoing: true
            ) == .cancel
        )
        #expect(
            AirDropLogic.decide(
                state: 1,
                progress: 0.4,
                sawMeaningfulProgress: true,
                isOutgoing: true
            ) == .continueOutgoing
        )
        #expect(
            AirDropLogic.decide(
                state: 1,
                progress: 0.4,
                sawMeaningfulProgress: true,
                isOutgoing: false
            ) == .continueReceiving
        )
    }
}
