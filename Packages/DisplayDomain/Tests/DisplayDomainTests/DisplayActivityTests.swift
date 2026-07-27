import XCTest
@testable import DisplayDomain

final class DisplayActivityTests: XCTestCase {
    func testAnAwakeDisplayIsAnActiveSurface() {
        XCTAssertTrue(DisplayActivity.isActiveSurface(cgIsActive: true, cgIsAsleep: false))
    }

    /// The regression that mattered: `CGDisplayIsActive` reads false while a display sleeps. Taken
    /// literally, an idle Mac looks like a Mac with zero displays — the always-one-active safety net
    /// then "recovers" a display the user deliberately turned off and clears the ledger remembering
    /// it, so the next real disconnect has nothing to restore and the user is left with no screen.
    func testASleepingDisplayStillCountsAsAnActiveSurface() {
        XCTAssertTrue(DisplayActivity.isActiveSurface(cgIsActive: false, cgIsAsleep: true))
    }

    func testASleepingDisplayThatAlsoReportsActiveIsActive() {
        XCTAssertTrue(DisplayActivity.isActiveSurface(cgIsActive: true, cgIsAsleep: true))
    }

    /// Neither active nor asleep: an online display that is not a usable surface (e.g. a mirrored
    /// secondary). The safety net may legitimately treat this as "not a surface of its own".
    func testAnInactiveAwakeDisplayIsNotAnActiveSurface() {
        XCTAssertFalse(DisplayActivity.isActiveSurface(cgIsActive: false, cgIsAsleep: false))
    }
}
