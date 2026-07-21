import XCTest
@testable import TopologyCore

final class LidStatePolicyTests: XCTestCase {
    func testActiveBuiltInPanelIsAlwaysOpen() {
        let state = LidStatePolicy.evaluate(
            builtInIsActive: true, hasBuiltInPanel: true, ambientLux: nil)
        XCTAssertEqual(state, .open)
    }

    func testReadableAmbientSensorIsOpenEvenWithPanelOff() {
        let state = LidStatePolicy.evaluate(
            builtInIsActive: false, hasBuiltInPanel: true, ambientLux: 120)
        XCTAssertEqual(state, .open)
    }

    func testDarkRoomZeroLuxIsStillOpenNotUnavailable() {
        // 0 lux is a legitimate ambient reading (dark room), not a failed read — see AmbientLight.swift.
        let state = LidStatePolicy.evaluate(
            builtInIsActive: false, hasBuiltInPanel: true, ambientLux: 0)
        XCTAssertEqual(state, .open)
    }

    func testInactivePanelWithUnreadableSensorIsClosed() {
        let state = LidStatePolicy.evaluate(
            builtInIsActive: false, hasBuiltInPanel: true, ambientLux: nil)
        XCTAssertEqual(state, .closed)
    }

    func testNoBuiltInPanelAtAllIsUnavailable() {
        let state = LidStatePolicy.evaluate(
            builtInIsActive: false, hasBuiltInPanel: false, ambientLux: nil)
        XCTAssertNil(state)
    }
}
