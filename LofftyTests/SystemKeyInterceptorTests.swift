//
//  SystemKeyInterceptorTests.swift
//  LofftyTests
//

import Testing

@testable import Loffty

@Suite("SystemKeyInterceptor")
struct SystemKeyInterceptorTests {
    @Test func adjustmentStepOptionShiftIsFine() {
        #expect(
            SystemKeyInterceptor.adjustmentStep(optionAndShift: true)
                == SystemKeyInterceptor.fineStep
        )
        #expect(
            SystemKeyInterceptor.adjustmentStep(optionAndShift: false)
                == SystemKeyInterceptor.normalStep
        )
    }
}
