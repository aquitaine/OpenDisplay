import XCTest
@testable import TopologyCore

final class TimedRevertGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func gate(seconds: Double = 5) -> TimedRevertGate<String> {
        TimedRevertGate(before: "ORIGINAL", deadline: t0.addingTimeInterval(seconds))
    }

    func testStartsPending() {
        let g = gate()
        XCTAssertTrue(g.isPending)
        XCTAssertEqual(g.resolution, .pending)
    }

    func testConfirmKeepsAndReportsTransition() {
        var g = gate()
        XCTAssertTrue(g.confirm())
        XCTAssertEqual(g.resolution, .kept)
        // A second confirm is a no-op and reports no transition.
        XCTAssertFalse(g.confirm())
    }

    func testRevertReturnsBeforeStateOnce() {
        var g = gate()
        XCTAssertEqual(g.revert(), "ORIGINAL")
        XCTAssertEqual(g.resolution, .reverted)
        // Already reverted → no further restore handed out.
        XCTAssertNil(g.revert())
    }

    func testTickBeforeDeadlineDoesNothing() {
        var g = gate(seconds: 5)
        XCTAssertNil(g.tick(now: t0.addingTimeInterval(4.9)))
        XCTAssertTrue(g.isPending)
    }

    func testTickAtOrAfterDeadlineReverts() {
        var g = gate(seconds: 5)
        XCTAssertEqual(g.tick(now: t0.addingTimeInterval(5)), "ORIGINAL")
        XCTAssertEqual(g.resolution, .reverted)
    }

    func testConfirmThenTimeoutStaysKept() {
        var g = gate(seconds: 5)
        XCTAssertTrue(g.confirm())
        // The deadline passing after a confirm must NOT restore — the user accepted the change.
        XCTAssertNil(g.tick(now: t0.addingTimeInterval(100)))
        XCTAssertEqual(g.resolution, .kept)
    }

    func testTimeoutThenConfirmStaysReverted() {
        var g = gate(seconds: 5)
        XCTAssertEqual(g.tick(now: t0.addingTimeInterval(6)), "ORIGINAL")
        // A late confirm can't un-revert.
        XCTAssertFalse(g.confirm())
        XCTAssertEqual(g.resolution, .reverted)
    }

    func testRestoreHappensAtMostOnceAcrossTickAndRevert() {
        var g = gate(seconds: 5)
        // Timeout fires the restore...
        XCTAssertNotNil(g.tick(now: t0.addingTimeInterval(5)))
        // ...and neither a later tick nor an explicit revert restores a second time.
        XCTAssertNil(g.tick(now: t0.addingTimeInterval(10)))
        XCTAssertNil(g.revert())
    }

    func testSecondsRemainingCountsDownAndClampsAtZero() {
        let g = gate(seconds: 5)
        XCTAssertEqual(g.secondsRemaining(now: t0), 5)
        XCTAssertEqual(g.secondsRemaining(now: t0.addingTimeInterval(2.1)), 3)
        XCTAssertEqual(g.secondsRemaining(now: t0.addingTimeInterval(5)), 0)
        XCTAssertEqual(g.secondsRemaining(now: t0.addingTimeInterval(99)), 0)
    }

    func testRestoredStateEqualsExactBefore() {
        // The gate hands back precisely the captured before-state (mode/origin/mirror/main, modeled
        // here as an opaque Equatable payload), so the host can restore the exact prior arrangement.
        struct Arrangement: Equatable { let mode: String; let origin: Int; let mirrored: Bool; let main: Int }
        let before = Arrangement(mode: "1920x1080", origin: 0, mirrored: false, main: 1)
        var g = TimedRevertGate(before: before, deadline: t0.addingTimeInterval(3))
        XCTAssertEqual(g.tick(now: t0.addingTimeInterval(3)), before)
    }
}
