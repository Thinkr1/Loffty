//
//  FmtTimeTests.swift
//  LofftyTests
//

import Testing

@testable import Loffty

@Suite("fmtTime")
struct FmtTimeTests {
    @Test(arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (65.0, "1:05"),
        (3599.0, "59:59"),
        (3600.0, "60:00"),
    ])
    func formatsFiniteSeconds(seconds: Double, expected: String) {
        #expect(fmtTime(seconds) == expected)
    }

    @Test func rejectsNonFiniteAndNegative() {
        #expect(fmtTime(-1) == "0:00")
        #expect(fmtTime(.nan) == "0:00")
        #expect(fmtTime(.infinity) == "0:00")
    }
}
