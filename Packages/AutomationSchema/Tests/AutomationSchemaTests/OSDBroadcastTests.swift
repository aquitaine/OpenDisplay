import XCTest
@testable import AutomationSchema

final class OSDBroadcastTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let broadcast = OSDBroadcast(kind: .brightness, value: 0.5, displayID: "cg:abc",
                                     displayName: "Desk", source: "mediaKey", timestamp: 1234)
        let data = try JSONEncoder().encode(broadcast)
        let decoded = try JSONDecoder().decode(OSDBroadcast.self, from: data)
        XCTAssertEqual(decoded, broadcast)
    }

    func testUserInfoRoundTrip() {
        let broadcast = OSDBroadcast(kind: .volume, value: 0.25, displayID: "cg:xyz",
                                     displayName: "Studio", source: "menu", timestamp: 99)
        let restored = OSDBroadcast(userInfo: broadcast.userInfo)
        XCTAssertEqual(restored, broadcast)
    }

    func testUserInfoMissingRequiredFieldIsNil() {
        var info = OSDBroadcast(kind: .mute, value: 0, displayID: "cg:1",
                                source: "cli", timestamp: 1).userInfo
        info["kind"] = nil
        XCTAssertNil(OSDBroadcast(userInfo: info))
    }

    func testUserInfoIgnoresUnknownKeys() {
        var info = OSDBroadcast(kind: .brightness, value: 0.7, displayID: "cg:1",
                                source: "appIntent", timestamp: 1).userInfo
        info["somethingNew"] = "ignored"
        XCTAssertNotNil(OSDBroadcast(userInfo: info))
    }

    func testValueIsClamped() {
        XCTAssertEqual(OSDBroadcast(kind: .brightness, value: 5, displayID: "d", source: "s", timestamp: 0).value, 1)
        XCTAssertEqual(OSDBroadcast(kind: .brightness, value: -3, displayID: "d", source: "s", timestamp: 0).value, 0)
    }

    func testVersionDefaultsToSchemaVersion() {
        let broadcast = OSDBroadcast(kind: .volume, value: 0.5, displayID: "d", source: "s", timestamp: 0)
        XCTAssertEqual(broadcast.version, OSDBroadcast.schemaVersion)
    }
}
