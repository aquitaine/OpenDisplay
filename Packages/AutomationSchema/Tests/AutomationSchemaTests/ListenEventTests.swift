import XCTest
@testable import AutomationSchema

final class ListenEventTests: XCTestCase {
    func testBrightnessEventCarriesBroadcastFieldsAndLeavesDisplaysNil() {
        let broadcast = OSDBroadcast(kind: .brightness, value: 0.62, displayID: "cg:abc",
                                     displayName: "Studio Display", source: "mediaKey", timestamp: 99)
        let event = ListenEvent.brightness(from: broadcast)
        XCTAssertEqual(event.event, .brightness)
        XCTAssertEqual(event.displayId, "cg:abc")
        XCTAssertEqual(event.displayName, "Studio Display")
        XCTAssertEqual(event.level, 0.62)
        XCTAssertEqual(event.source, "mediaKey")
        XCTAssertNil(event.displays)
    }

    func testConfigEventCarriesDisplaysAndLeavesBrightnessFieldsNil() {
        let displays = [ListenEvent.DisplaySummary(id: "cg:abc", active: true, main: true, mode: "3840x2160@60")]
        let event = ListenEvent.config(at: 42, displays: displays)
        XCTAssertEqual(event.event, .config)
        XCTAssertEqual(event.displays, displays)
        XCTAssertNil(event.displayId)
        XCTAssertNil(event.level)
        XCTAssertNil(event.source)
    }

    func testVersionDefaultsToSchemaVersion() {
        let event = ListenEvent.config(at: 0, displays: [])
        XCTAssertEqual(event.version, ListenEvent.schemaVersion)
    }

    func testCodableRoundTripForBrightness() throws {
        let broadcast = OSDBroadcast(kind: .brightness, value: 0.3, displayID: "cg:1",
                                     source: "cli", timestamp: 5)
        let event = ListenEvent.brightness(from: broadcast)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ListenEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testCodableRoundTripForConfig() throws {
        let displays = [
            ListenEvent.DisplaySummary(id: "cg:1", active: true, main: true, mode: "1920x1080@60"),
            ListenEvent.DisplaySummary(id: "cg:2", active: false, main: false, mode: nil),
        ]
        let event = ListenEvent.config(at: 7, displays: displays)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ListenEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testEncodedConfigLineOmitsBrightnessOnlyKeys() throws {
        let event = ListenEvent.config(at: 0, displays: [])
        guard let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(event)) as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        XCTAssertEqual(Set(json.keys), ["version", "event", "timestamp", "displays"])
    }

    func testEncodedBrightnessLineOmitsDisplaysKey() throws {
        let broadcast = OSDBroadcast(kind: .brightness, value: 0.5, displayID: "cg:1",
                                     source: "cli", timestamp: 0)
        let event = ListenEvent.brightness(from: broadcast)
        guard let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(event)) as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        XCTAssertEqual(Set(json.keys), ["version", "event", "timestamp", "displayId", "level", "source"])
    }
}
