import XCTest
@testable import AutomationSchema

final class DDCWriteVerificationTests: XCTestCase {
    func testExactMatchIsApplied() {
        XCTAssertEqual(DDCWriteVerification.outcome(target: 11, readback: 11), .applied)
    }

    func testMismatchIsIgnoredWithPanelValue() {
        // Live LG case: preset 4 requested, panel stayed on 11.
        XCTAssertEqual(DDCWriteVerification.outcome(target: 4, readback: 11), .ignored(actual: 11))
    }

    func testNilReadbackIsUnknownNotIgnored() {
        // A flaky read must never be reported as a rejected write.
        XCTAssertEqual(DDCWriteVerification.outcome(target: 40, readback: nil), .unknown)
        XCTAssertEqual(DDCWriteVerification.outcome(target: 40, readback: nil, tolerance: 1), .unknown)
    }

    func testToleranceAbsorbsRoundingBothWays() {
        XCTAssertEqual(DDCWriteVerification.outcome(target: 50, readback: 51, tolerance: 1), .applied)
        XCTAssertEqual(DDCWriteVerification.outcome(target: 50, readback: 49, tolerance: 1), .applied)
        XCTAssertEqual(DDCWriteVerification.outcome(target: 50, readback: 52, tolerance: 1), .ignored(actual: 52))
    }

    func testDefaultToleranceIsExact() {
        XCTAssertEqual(DDCWriteVerification.outcome(target: 5, readback: 6), .ignored(actual: 6))
    }

    func testNegativeToleranceIsTreatedAsExact() {
        XCTAssertEqual(DDCWriteVerification.outcome(target: 5, readback: 5, tolerance: -3), .applied)
    }

    func testIgnoredContrastWrite() {
        // Live LG case: contrast 40 written, panel read back 18.
        XCTAssertEqual(DDCWriteVerification.outcome(target: 40, readback: 18, tolerance: 1), .ignored(actual: 18))
    }
}
