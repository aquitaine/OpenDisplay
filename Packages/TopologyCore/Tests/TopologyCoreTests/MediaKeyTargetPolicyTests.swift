import XCTest
@testable import DisplayDomain
@testable import TopologyCore

final class MediaKeyTargetPolicyTests: XCTestCase {
    private func obs(
        _ id: String, active: Bool = true, main: Bool = false, builtIn: Bool = false,
        x: Int = 0, y: Int = 0, w: Int = 1920, h: Int = 1080
    ) -> DisplayObservation {
        DisplayObservation(
            recordID: DisplayRecordID(rawValue: id),
            isActive: active,
            origin: DisplayOrigin(x: x, y: y),
            mode: DisplayMode(pixelWidth: w, pixelHeight: h, pointWidth: w, pointHeight: h,
                              refreshHz: 60, isHiDPI: false),
            isMain: main,
            displayClass: builtIn ? .builtIn : .external,
            generation: .initial
        )
    }

    func testUnderCursorPicksDisplayContainingPoint() {
        let builtIn = obs("builtin", main: true, builtIn: true, x: 0, y: 0)
        let ext = obs("ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 2000, y: 100), mode: .underCursor, volumeCapable: [])
        XCTAssertEqual(target?.recordID.rawValue, "ext")
    }

    func testUnderCursorFallsBackToMainWhenCursorOutsideAll() {
        let builtIn = obs("builtin", main: true, builtIn: true, x: 0, y: 0)
        let ext = obs("ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 99999, y: 99999), mode: .underCursor, volumeCapable: [])
        XCTAssertEqual(target?.recordID.rawValue, "builtin")
    }

    func testMainDisplayModeAlwaysPicksMain() {
        let builtIn = obs("builtin", builtIn: true, x: 0, y: 0)
        let ext = obs("ext", main: true, x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessDown, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 100, y: 100), mode: .mainDisplay, volumeCapable: [])
        XCTAssertEqual(target?.recordID.rawValue, "ext")
    }

    func testBuiltInAlwaysModePicksBuiltIn() {
        let builtIn = obs("builtin", builtIn: true, x: 0, y: 0)
        let ext = obs("ext", main: true, x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 2000, y: 100), mode: .builtInAlways, volumeCapable: [])
        XCTAssertEqual(target?.recordID.rawValue, "builtin")
    }

    func testSingleDisplayResolvesToItself() {
        let only = obs("only", main: true, builtIn: true)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [only], cursor: nil, mode: .underCursor, volumeCapable: [])
        XCTAssertEqual(target?.recordID.rawValue, "only")
    }

    func testVolumeRoutesOnlyToDDCCapableDisplay() {
        let ext = obs("ext", main: true)
        let capable = MediaKeyTargetPolicy.target(
            for: .volumeUp, in: [ext], cursor: nil, mode: .mainDisplay,
            volumeCapable: [DisplayRecordID(rawValue: "ext")])
        XCTAssertEqual(capable?.recordID.rawValue, "ext")
    }

    func testVolumeOnNonCapableTargetPassesThrough() {
        let builtIn = obs("builtin", main: true, builtIn: true)
        let target = MediaKeyTargetPolicy.target(
            for: .volumeUp, in: [builtIn], cursor: nil, mode: .mainDisplay, volumeCapable: [])
        XCTAssertNil(target, "volume key with no DDC-audio-capable target should pass through (nil)")
    }

    func testInactiveAndEmptyYieldNil() {
        XCTAssertNil(MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [], cursor: nil, mode: .mainDisplay, volumeCapable: []))
        let off = obs("off", active: false)
        XCTAssertNil(MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [off], cursor: nil, mode: .mainDisplay, volumeCapable: []))
    }
}
