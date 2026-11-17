import TopologyCore
import XCTest

final class SessionActivityGateTests: XCTestCase {
    func testDefaultsToActive() {
        let gate = SessionActivityGate()
        XCTAssertTrue(gate.isActive)
        XCTAssertTrue(gate.permitsAutomaticDisplayActions)
        XCTAssertFalse(gate.attributesDisplayChangesElsewhere)
    }

    func testSwitchingAwaySuspendsAndBlocksAutomaticActions() {
        var gate = SessionActivityGate()
        XCTAssertEqual(gate.update(isActive: false), .suspended)
        XCTAssertFalse(gate.permitsAutomaticDisplayActions)
        XCTAssertTrue(gate.attributesDisplayChangesElsewhere)
    }

    func testSwitchingBackResumes() {
        var gate = SessionActivityGate()
        _ = gate.update(isActive: false)
        XCTAssertEqual(gate.update(isActive: true), .resumed)
        XCTAssertTrue(gate.permitsAutomaticDisplayActions)
        XCTAssertFalse(gate.attributesDisplayChangesElsewhere)
    }

    func testRepeatedNotificationsDoNotRefire() {
        var gate = SessionActivityGate()
        XCTAssertEqual(gate.update(isActive: true), .unchanged)
        _ = gate.update(isActive: false)
        XCTAssertEqual(gate.update(isActive: false), .unchanged)
        _ = gate.update(isActive: true)
        XCTAssertEqual(gate.update(isActive: true), .unchanged)
    }

    func testLaunchedInBackgroundSessionResumesOnFirstActivation() {
        var gate = SessionActivityGate(isActive: SessionActivityGate.isActive(onConsole: false))
        XCTAssertFalse(gate.permitsAutomaticDisplayActions)
        XCTAssertEqual(gate.update(isActive: true), .resumed)
    }

    func testConsoleFlagParsing() {
        XCTAssertTrue(SessionActivityGate.isActive(onConsole: true))
        XCTAssertFalse(SessionActivityGate.isActive(onConsole: false))
        // Unknown must never switch the foreground copy's automations off.
        XCTAssertTrue(SessionActivityGate.isActive(onConsole: nil))
    }
}
