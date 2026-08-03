import XCTest
@testable import DisplayDomain

/// The naming ladder every surface shows a display through, and the `cg:<uuid>` id form that lets a
/// display which isn't plugged in be looked up at all. Both exist for the same reason: a group
/// member the user cannot see must still read as a monitor, not as a UUID.
final class DisplayNamingTests: XCTestCase {
    private func record(alias: String? = nil, model: String? = nil,
                        displayClass: DisplayClass = .external) -> DisplayRecord {
        DisplayRecord(id: DisplayRecordID(rawValue: "disp_1"), alias: alias,
                      fingerprint: DisplayFingerprint(modelName: model), displayClass: displayClass)
    }

    private func mode(width: Int = 3840, height: Int = 2160) -> DisplayMode {
        DisplayMode(pixelWidth: width, pixelHeight: height, pointWidth: width / 2,
                    pointHeight: height / 2, refreshHz: 60, isHiDPI: true)
    }

    // MARK: - The naming ladder

    func testAliasWinsOverEveryOtherName() {
        XCTAssertEqual(record(alias: "Desk", model: "U2720Q").friendlyName(mode: mode()), "Desk")
    }

    func testAnEmptyAliasFallsThroughToTheModelName() {
        XCTAssertEqual(record(alias: "", model: "U2720Q").friendlyName(), "U2720Q")
    }

    func testModelNameIsUsedWhenThereIsNoAlias() {
        XCTAssertEqual(record(model: "U2720Q").friendlyName(mode: mode()), "U2720Q")
    }

    func testAnUnnamedBuiltInIsNamedAsTheBuiltIn() {
        XCTAssertEqual(record(displayClass: .builtIn).friendlyName(), "Built-in Display")
    }

    func testAnUnnamedConnectedDisplayFallsBackToClassAndResolution() {
        XCTAssertEqual(record().friendlyName(mode: mode()), "External 3840×2160")
    }

    /// The absent-member case: no live mode to describe, and still no raw record id — a
    /// `cg:37D8832A-2D66-…` in a membership row identifies nothing to the person reading it.
    func testAnUnnamedAbsentDisplayFallsBackToItsClassAlone() {
        XCTAssertEqual(record().friendlyName(), "External display")
        XCTAssertEqual(record(displayClass: .airplay).friendlyName(), "Airplay display")
    }

    func testNoNamingPathEverReturnsTheRawRecordID() {
        let unnamed = record(displayClass: .unknown)
        XCTAssertFalse(unnamed.friendlyName().contains(unnamed.id.rawValue))
        XCTAssertFalse(unnamed.friendlyName(mode: mode()).contains(unnamed.id.rawValue))
    }

    // MARK: - The cg:<uuid> observation id

    func testACGUUIDRoundTripsThroughTheObservationIDForm() {
        let id = DisplayRecordID.forCGUUID("37D8832A-2D66")
        XCTAssertEqual(id.rawValue, "cg:37D8832A-2D66")
        XCTAssertEqual(id.cgUUID, "37D8832A-2D66")
    }

    func testIDFormsWithoutACGUUIDReportNone() {
        XCTAssertNil(DisplayRecordID(rawValue: "cgid:7").cgUUID)
        XCTAssertNil(DisplayRecordID(rawValue: "disp_1700000000_abc").cgUUID)
        XCTAssertNil(DisplayRecordID.generate().cgUUID)
    }
}
