import XCTest
@testable import AutomationSchema

final class DDCProbeTrackerTests: XCTestCase {
    private let sharpness: UInt8 = 0x87

    func testUnknownCodeIsAlwaysProbed() {
        var tracker = DDCProbeTracker()
        XCTAssertTrue(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.admitProbe(sharpness))  // admitting is not recording
    }

    func testSingleFailureIsNotUnsupported() {
        // One failed read can be a waking panel or a busy bus — must not negatively cache.
        var tracker = DDCProbeTracker(strikeLimit: 2)
        tracker.recordFailure(sharpness)
        XCTAssertTrue(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.unsupportedCodes.isEmpty)
    }

    func testStrikeLimitFailuresNegativelyCache() {
        var tracker = DDCProbeTracker(strikeLimit: 2, recheckInterval: 8)
        tracker.recordFailure(sharpness)
        tracker.recordFailure(sharpness)
        XCTAssertEqual(tracker.unsupportedCodes, [sharpness])
        XCTAssertFalse(tracker.admitProbe(sharpness))
    }

    func testSuccessResetsStrikesAndNegativeCache() {
        var tracker = DDCProbeTracker(strikeLimit: 2)
        tracker.recordFailure(sharpness)
        tracker.recordSuccess(sharpness)
        tracker.recordFailure(sharpness)  // strike count restarted — still only 1
        XCTAssertTrue(tracker.admitProbe(sharpness))

        tracker.recordFailure(sharpness)  // now cached...
        XCTAssertFalse(tracker.admitProbe(sharpness))
        tracker.recordSuccess(sharpness)  // ...until it answers again
        XCTAssertTrue(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.unsupportedCodes.isEmpty)
    }

    func testPeriodicRecheckReadmitsCachedCode() {
        var tracker = DDCProbeTracker(strikeLimit: 1, recheckInterval: 3)
        tracker.recordFailure(sharpness)
        // Skipped, skipped, then the 3rd admission goes through as a recheck — repeatably.
        XCTAssertFalse(tracker.admitProbe(sharpness))
        XCTAssertFalse(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.admitProbe(sharpness))
        XCTAssertFalse(tracker.admitProbe(sharpness))
        XCTAssertFalse(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.admitProbe(sharpness))
    }

    func testCodesAreTrackedIndependently() {
        var tracker = DDCProbeTracker(strikeLimit: 1)
        tracker.recordFailure(sharpness)
        XCTAssertFalse(tracker.admitProbe(sharpness))
        XCTAssertTrue(tracker.admitProbe(0x12))  // contrast untouched
    }

    func testDegenerateLimitsClampSafely() {
        var tracker = DDCProbeTracker(strikeLimit: 0, recheckInterval: 0)
        tracker.recordFailure(sharpness)          // clamped strikeLimit 1 → cached immediately
        XCTAssertEqual(tracker.unsupportedCodes, [sharpness])
        XCTAssertTrue(tracker.admitProbe(sharpness))  // clamped recheckInterval 1 → every admission rechecks
    }
}
