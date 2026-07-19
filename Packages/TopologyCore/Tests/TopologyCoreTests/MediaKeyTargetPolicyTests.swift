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

    private func rid(_ id: String) -> DisplayRecordID { DisplayRecordID(rawValue: id) }

    // MARK: - Brightness (follows the target mode; unaffected by audio routing)

    func testUnderCursorPicksDisplayContainingPoint() {
        let builtIn = obs("builtin", main: true, builtIn: true, x: 0, y: 0)
        let ext = obs("ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 2000, y: 100), mode: .underCursor, volumeCapable: [], audioTarget: nil)
        XCTAssertEqual(target?.recordID.rawValue, "ext")
    }

    func testUnderCursorFallsBackToMainWhenCursorOutsideAll() {
        let builtIn = obs("builtin", main: true, builtIn: true, x: 0, y: 0)
        let ext = obs("ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 99999, y: 99999), mode: .underCursor, volumeCapable: [], audioTarget: nil)
        XCTAssertEqual(target?.recordID.rawValue, "builtin")
    }

    func testMainDisplayModeAlwaysPicksMain() {
        let builtIn = obs("builtin", builtIn: true, x: 0, y: 0)
        let ext = obs("ext", main: true, x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessDown, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 100, y: 100), mode: .mainDisplay, volumeCapable: [], audioTarget: nil)
        XCTAssertEqual(target?.recordID.rawValue, "ext")
    }

    func testBuiltInAlwaysModePicksBuiltIn() {
        let builtIn = obs("builtin", builtIn: true, x: 0, y: 0)
        let ext = obs("ext", main: true, x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 2000, y: 100), mode: .builtInAlways, volumeCapable: [], audioTarget: nil)
        XCTAssertEqual(target?.recordID.rawValue, "builtin")
    }

    func testSingleDisplayResolvesToItself() {
        let only = obs("only", main: true, builtIn: true)
        let target = MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [only], cursor: nil, mode: .underCursor, volumeCapable: [], audioTarget: nil)
        XCTAssertEqual(target?.recordID.rawValue, "only")
    }

    // MARK: - Volume (follows the default-audio display, ignoring mode/cursor)

    func testVolumeRoutesToAudioTargetRegardlessOfMode() {
        // Cursor + main are on the built-in, but audio plays through the external → drive the external.
        let builtIn = obs("builtin", main: true, builtIn: true, x: 0, y: 0)
        let ext = obs("ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .volumeUp, in: [builtIn, ext],
            cursor: DisplayOrigin(x: 100, y: 100), mode: .builtInAlways,
            volumeCapable: [rid("ext")], audioTarget: rid("ext"))
        XCTAssertEqual(target?.recordID.rawValue, "ext")
    }

    func testVolumeIgnoresMainWhenAudioIsElsewhere() {
        let mainExt = obs("main-ext", main: true, x: 0, y: 0)
        let audioExt = obs("audio-ext", x: 1920, y: 0)
        let target = MediaKeyTargetPolicy.target(
            for: .volumeDown, in: [mainExt, audioExt],
            cursor: DisplayOrigin(x: 50, y: 50), mode: .mainDisplay,
            volumeCapable: [rid("main-ext"), rid("audio-ext")], audioTarget: rid("audio-ext"))
        XCTAssertEqual(target?.recordID.rawValue, "audio-ext")
    }

    func testVolumePassesThroughWhenNoAudioTarget() {
        // Default output is not a display (e.g. speakers/AirPods) → nil, let macOS handle it.
        let ext = obs("ext", main: true)
        let target = MediaKeyTargetPolicy.target(
            for: .volumeUp, in: [ext], cursor: nil, mode: .mainDisplay,
            volumeCapable: [rid("ext")], audioTarget: nil)
        XCTAssertNil(target)
    }

    func testVolumePassesThroughWhenAudioTargetNotVolumeCapable() {
        let ext = obs("ext", main: true)
        let target = MediaKeyTargetPolicy.target(
            for: .volumeUp, in: [ext], cursor: nil, mode: .mainDisplay,
            volumeCapable: [], audioTarget: rid("ext"))
        XCTAssertNil(target, "audio display that can't take DDC volume should pass through")
    }

    func testVolumePassesThroughWhenAudioTargetInactive() {
        let ext = obs("ext", active: false)
        let other = obs("other", main: true)
        let target = MediaKeyTargetPolicy.target(
            for: .muteToggle, in: [ext, other], cursor: nil, mode: .mainDisplay,
            volumeCapable: [rid("ext")], audioTarget: rid("ext"))
        XCTAssertNil(target, "audio display that is inactive should pass through")
    }

    func testInactiveAndEmptyYieldNil() {
        XCTAssertNil(MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [], cursor: nil, mode: .mainDisplay, volumeCapable: [], audioTarget: nil))
        let off = obs("off", active: false)
        XCTAssertNil(MediaKeyTargetPolicy.target(
            for: .brightnessUp, in: [off], cursor: nil, mode: .mainDisplay, volumeCapable: [], audioTarget: nil))
    }
}
