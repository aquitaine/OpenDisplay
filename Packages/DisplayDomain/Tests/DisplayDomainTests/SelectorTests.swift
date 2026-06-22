import XCTest
@testable import DisplayDomain

final class SelectorTests: XCTestCase {
    func testParsesSchemes() throws {
        XCTAssertEqual(try DisplaySelector.parse("id:disp_42"), .id(DisplayRecordID(rawValue: "disp_42")))
        XCTAssertEqual(try DisplaySelector.parse("alias:DeskLeft"), .alias("DeskLeft"))
        XCTAssertEqual(try DisplaySelector.parse("tag:studio"), .tag("studio"))
        XCTAssertEqual(try DisplaySelector.parse("name:\"LG HDR 4K\""), .name("LG HDR 4K"))
        XCTAssertEqual(try DisplaySelector.parse("state:managedOffline"), .state(.managedOffline))
    }

    func testParsesBareRoles() throws {
        XCTAssertEqual(try DisplaySelector.parse("main"), .role(.main))
        XCTAssertEqual(try DisplaySelector.parse("builtin"), .role(.builtin))
        XCTAssertEqual(try DisplaySelector.parse("pointer"), .role(.pointer))
        XCTAssertEqual(try DisplaySelector.parse("focus"), .role(.focus))
    }

    func testParsesFingerprint() throws {
        let selector = try DisplaySelector.parse("vendor:610 product:12345 serial:ABC")
        XCTAssertEqual(selector, .fingerprint(vendor: 610, product: 12345, serial: "ABC"))
    }

    func testParsesTopologyRelative() throws {
        XCTAssertEqual(try DisplaySelector.parse("leftOf:alias:Center"), .topology(edge: .leftOf, of: "Center"))
        XCTAssertEqual(try DisplaySelector.parse("rightOf:Center"), .topology(edge: .rightOf, of: "Center"))
    }

    func testSetSelectorClassification() {
        XCTAssertTrue(DisplaySelector.tag("studio").isSetSelector)
        XCTAssertTrue(DisplaySelector.state(.active).isSetSelector)
        XCTAssertFalse(DisplaySelector.id(DisplayRecordID(rawValue: "x")).isSetSelector)
        XCTAssertFalse(DisplaySelector.role(.main).isSetSelector)
    }

    func testErrors() {
        XCTAssertThrowsError(try DisplaySelector.parse("")) { error in
            XCTAssertEqual(error as? SelectorParseError, .empty)
        }
        XCTAssertThrowsError(try DisplaySelector.parse("bogus:value")) { error in
            XCTAssertEqual(error as? SelectorParseError, .unknownScheme("bogus"))
        }
        XCTAssertThrowsError(try DisplaySelector.parse("noscheme")) { error in
            XCTAssertEqual(error as? SelectorParseError, .malformed("noscheme"))
        }
    }
}
