import XCTest
@testable import AutomationSchema

final class DDCPowerModeTests: XCTestCase {
    func testVCPValuesMatchMCCSSpec() {
        XCTAssertEqual(DDCPowerMode.on.vcpValue, 0x01)
        XCTAssertEqual(DDCPowerMode.standby.vcpValue, 0x04)
        XCTAssertEqual(DDCPowerMode.off.vcpValue, 0x05)
    }

    func testParsesCanonicalTokens() {
        XCTAssertEqual(DDCPowerMode(parsing: "on"), .on)
        XCTAssertEqual(DDCPowerMode(parsing: "standby"), .standby)
        XCTAssertEqual(DDCPowerMode(parsing: "off"), .off)
    }

    func testParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(DDCPowerMode(parsing: " ON "), .on)
        XCTAssertEqual(DDCPowerMode(parsing: "Off"), .off)
        XCTAssertEqual(DDCPowerMode(parsing: "StandBy"), .standby)
    }

    func testParsingAcceptsSleepAndDpmsAliasesForStandby() {
        XCTAssertEqual(DDCPowerMode(parsing: "sleep"), .standby)
        XCTAssertEqual(DDCPowerMode(parsing: "dpms"), .standby)
    }

    func testParsingRejectsUnknownTokens() {
        XCTAssertNil(DDCPowerMode(parsing: ""))
        XCTAssertNil(DDCPowerMode(parsing: "suspend"))
        XCTAssertNil(DDCPowerMode(parsing: "0x05"))
        XCTAssertNil(DDCPowerMode(parsing: "power"))
    }

    func testLabels() {
        XCTAssertEqual(DDCPowerMode.on.label, "On")
        XCTAssertEqual(DDCPowerMode.standby.label, "Standby")
        XCTAssertEqual(DDCPowerMode.off.label, "Off")
    }

    func testAllCasesCoveredAndRoundTripViaRawValue() throws {
        // Every case parses from its own rawValue and exposes a distinct VCP value.
        let values = Set(DDCPowerMode.allCases.map(\.vcpValue))
        XCTAssertEqual(values.count, DDCPowerMode.allCases.count)
        for mode in DDCPowerMode.allCases {
            XCTAssertEqual(DDCPowerMode(parsing: mode.rawValue), mode)
        }
    }
}
