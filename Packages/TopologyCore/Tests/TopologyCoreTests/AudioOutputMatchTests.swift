import XCTest
@testable import DisplayDomain
@testable import TopologyCore

final class AudioOutputMatchTests: XCTestCase {
    private func obs(_ id: String, active: Bool = true, builtIn: Bool = false) -> DisplayObservation {
        DisplayObservation(
            recordID: DisplayRecordID(rawValue: id),
            isActive: active,
            displayClass: builtIn ? .builtIn : .external,
            generation: .initial
        )
    }

    private func rid(_ id: String) -> DisplayRecordID { DisplayRecordID(rawValue: id) }

    func testExactNameMatchCaseInsensitive() {
        let ext = obs("ext")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "dell u2720q", transport: .hdmi,
            displays: [obs("builtin", builtIn: true), ext],
            names: [rid("ext"): "Dell U2720Q", rid("builtin"): "Built-in Display"])
        XCTAssertEqual(match, rid("ext"))
    }

    func testPrefixContainsMatch() {
        // Audio device name contains the display's product name.
        let ext = obs("ext")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "LG UltraFine Display Audio", transport: .displayPort,
            displays: [ext], names: [rid("ext"): "LG UltraFine"])
        XCTAssertEqual(match, rid("ext"))
    }

    func testDisplayNameContainsDeviceName() {
        // Display name is the longer of the two.
        let ext = obs("ext")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "Studio Display", transport: .hdmi,
            displays: [ext], names: [rid("ext"): "Apple Studio Display (Main)"])
        XCTAssertEqual(match, rid("ext"))
    }

    func testWrongTransportIsNil() {
        let ext = obs("ext")
        for transport in [AudioOutputTransport.other] {
            XCTAssertNil(AudioOutputDisplayMatcher.match(
                deviceName: "Dell U2720Q", transport: transport,
                displays: [ext], names: [rid("ext"): "Dell U2720Q"]),
                "non-HDMI/DP transport must never match a display")
        }
    }

    func testSingleExternalFallbackWhenNoNameMatch() {
        // Name doesn't match, but there's exactly one external → HDMI audio must be coming through it.
        let ext = obs("ext")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "HDMI", transport: .hdmi,
            displays: [obs("builtin", builtIn: true), ext],
            names: [rid("ext"): "Some Monitor", rid("builtin"): "Built-in Display"])
        XCTAssertEqual(match, rid("ext"))
    }

    func testTwoExternalsNoNameMatchIsAmbiguousNil() {
        let a = obs("a")
        let b = obs("b")
        XCTAssertNil(AudioOutputDisplayMatcher.match(
            deviceName: "HDMI Audio", transport: .hdmi,
            displays: [a, b],
            names: [rid("a"): "Monitor A", rid("b"): "Monitor B"]),
            "two externals with no name match → don't guess")
    }

    func testTwoExternalsAmbiguousNameMatchIsNil() {
        // Both display names contain the device name → ambiguous.
        let a = obs("a")
        let b = obs("b")
        XCTAssertNil(AudioOutputDisplayMatcher.match(
            deviceName: "Dell", transport: .displayPort,
            displays: [a, b],
            names: [rid("a"): "Dell U2720Q", rid("b"): "Dell P2419H"]),
            "two name matches → ambiguous, pass through")
    }

    func testNameMatchWinsWhenSecondExternalDoesNotMatch() {
        let a = obs("a")
        let b = obs("b")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "Dell U2720Q", transport: .hdmi,
            displays: [a, b],
            names: [rid("a"): "Dell U2720Q", rid("b"): "LG UltraFine"])
        XCTAssertEqual(match, rid("a"))
    }

    func testNoExternalDisplaysIsNil() {
        XCTAssertNil(AudioOutputDisplayMatcher.match(
            deviceName: "HDMI", transport: .hdmi,
            displays: [obs("builtin", builtIn: true)],
            names: [rid("builtin"): "Built-in Display"]))
    }

    func testInactiveExternalIsNotACandidate() {
        // The only external is inactive → no candidate, even with a matching name.
        let ext = obs("ext", active: false)
        XCTAssertNil(AudioOutputDisplayMatcher.match(
            deviceName: "Dell U2720Q", transport: .hdmi,
            displays: [ext], names: [rid("ext"): "Dell U2720Q"]))
    }

    func testEmptyDeviceNameFallsBackToSingleExternal() {
        let ext = obs("ext")
        let match = AudioOutputDisplayMatcher.match(
            deviceName: "", transport: .displayPort,
            displays: [ext], names: [rid("ext"): "Dell U2720Q"])
        XCTAssertEqual(match, rid("ext"))
    }
}
