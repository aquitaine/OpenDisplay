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

    // MARK: - macOS's phantom display

    /// Captured from real hardware the moment the last external was unplugged while the built-in
    /// was disabled: macOS substitutes a placeholder rather than reporting zero displays, so the
    /// safety net's "nothing is active" condition could never become true and the user was left
    /// staring at a dark screen.
    func testTheMacOSPlaceholderIsRecognised() {
        XCTAssertTrue(DisplayActivity.isVirtualPlaceholder(
            vendorNumber: 1_970_170_734,   // "unkn"
            modelNumber: 1_986_622_068,    // "virt"
            modeCount: 1))
    }

    func testTheVendorAndModelTagsSpellUnknownAndVirtual() {
        XCTAssertEqual(DisplayActivity.placeholderVendor, 1_970_170_734)
        XCTAssertEqual(DisplayActivity.placeholderModel, 1_986_622_068)
    }

    /// A single reported mode is the corroborating signal — real panels report dozens.
    func testASingleModeDisplayIsTreatedAsAPlaceholder() {
        XCTAssertTrue(DisplayActivity.isVirtualPlaceholder(
            vendorNumber: 19_501, modelNumber: 3_383, modeCount: 1))
    }

    /// The real external captured alongside the phantom: 48 modes, genuine vendor/model.
    func testARealExternalIsNotAPlaceholder() {
        XCTAssertFalse(DisplayActivity.isVirtualPlaceholder(
            vendorNumber: 19_501, modelNumber: 3_383, modeCount: 48))
    }

    /// The real built-in captured in the same run: 60 modes.
    func testARealBuiltInIsNotAPlaceholder() {
        XCTAssertFalse(DisplayActivity.isVirtualPlaceholder(
            vendorNumber: 1_552, modelNumber: 41_054, modeCount: 60))
    }
}
