import XCTest
@testable import AutomationSchema

final class DDCBindingPolicyTests: XCTestCase {
    func testInPlaneWithFewFailuresKeepsBinding() {
        // A busy panel NAKs a call or two; that must not churn the binding.
        for failures in 0...2 {
            XCTAssertFalse(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: failures),
                           "\(failures) failures")
            XCTAssertNil(DDCBindingPolicy.rebindReason(serviceInPlane: true, consecutiveIOFailures: failures))
        }
    }

    func testServiceOutOfPlaneRebinds() {
        // Live LG case: the proxy was re-created during DarkWake; the old one is detached.
        XCTAssertTrue(DDCBindingPolicy.shouldRebind(serviceInPlane: false, consecutiveIOFailures: 0))
        XCTAssertEqual(DDCBindingPolicy.rebindReason(serviceInPlane: false, consecutiveIOFailures: 0), .serviceGone)
    }

    func testThreeFailuresRebind() {
        XCTAssertTrue(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: 3))
        XCTAssertEqual(DDCBindingPolicy.rebindReason(serviceInPlane: true, consecutiveIOFailures: 3), .ioFailures)
        XCTAssertEqual(DDCBindingPolicy.rebindReason(serviceInPlane: true, consecutiveIOFailures: 40), .ioFailures)
    }

    func testServiceGoneOutranksFailureRun() {
        XCTAssertEqual(DDCBindingPolicy.rebindReason(serviceInPlane: false, consecutiveIOFailures: 9), .serviceGone)
    }

    func testCustomFailureLimit() {
        XCTAssertFalse(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: 4, failureLimit: 5))
        XCTAssertTrue(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: 5, failureLimit: 5))
    }

    func testNonPositiveFailureLimitStillNeedsAFailure() {
        // A misconfigured limit must not rebind a healthy binding on every call.
        XCTAssertFalse(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: 0, failureLimit: 0))
        XCTAssertTrue(DDCBindingPolicy.shouldRebind(serviceInPlane: true, consecutiveIOFailures: 1, failureLimit: 0))
    }

    func testIsNewBinding() {
        XCTAssertTrue(DDCBindingPolicy.isNewBinding(previousEntryID: 0x1_0000_147d, currentEntryID: 0x1_0003_d0ea))
        XCTAssertFalse(DDCBindingPolicy.isNewBinding(previousEntryID: 0x1_0000_147d, currentEntryID: 0x1_0000_147d))
        XCTAssertTrue(DDCBindingPolicy.isNewBinding(previousEntryID: nil, currentEntryID: 0x1_0000_147d))
    }

    func testReasonRawValuesAreTheTimelineSpelling() {
        XCTAssertEqual(DDCBindingPolicy.Reason.serviceGone.rawValue, "serviceGone")
        XCTAssertEqual(DDCBindingPolicy.Reason.ioFailures.rawValue, "ioFailures")
        XCTAssertEqual(DDCBindingPolicy.Reason.wake.rawValue, "wake")
    }
}
