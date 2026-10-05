import XCTest
@testable import TopologyCore

final class DisplayEventLogTests: XCTestCase {
    private func row(_ id: UInt32, online: Bool = true, active: Bool = true) -> DisplayEventLog.Row {
        DisplayEventLog.Row(id: id, uuid: "U\(id)", vendor: 0x4C2D, model: 1, builtIn: false,
                            online: online, active: active, asleep: false, main: id == 1,
                            mirrorOf: nil, width: 3440, height: 1440, refreshHz: 120, modeCount: 48)
    }

    func testAnEntryCountsOnlineAndActiveDisplaysForItself() {
        let entry = DisplayEventLog.Entry(at: Date(timeIntervalSince1970: 0), reason: "topology",
                                          owed: ["Desk"], displays: [row(1), row(2, active: false)])
        XCTAssertEqual(entry.online, 2)
        XCTAssertEqual(entry.active, 1)
    }

    func testALineIsOneJSONObjectThatRoundTrips() throws {
        let entry = DisplayEventLog.Entry(at: Date(timeIntervalSince1970: 1_800_000_000),
                                          reason: "reconnect:failed", owed: [], displays: [row(3)])
        let line = try XCTUnwrap(DisplayEventLog.line(for: entry))
        XCTAssertFalse(line.contains("\n"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(DisplayEventLog.Entry.self, from: Data(line.utf8)), entry)
    }

    func testAShortLogIsLeftAlone() {
        XCTAssertNil(DisplayEventLog.trimmed("a\nb\n", rotateAtBytes: 100, keepLines: 1))
    }

    func testAnOverlongLogKeepsOnlyItsNewestLines() {
        let contents = (1...10).map { "line-\($0)" }.joined(separator: "\n") + "\n"
        XCTAssertEqual(DisplayEventLog.trimmed(contents, rotateAtBytes: 10, keepLines: 3),
                       "line-8\nline-9\nline-10\n")
    }

    func testAppendingWritesOneLinePerEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-events-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiskDisplayEventLog(directory: directory)
        for reason in ["launch", "topology"] {
            await log.append(DisplayEventLog.Entry(at: Date(), reason: reason, owed: [], displays: [row(1)]))
        }
        let contents = try String(contentsOf: directory.appendingPathComponent(DisplayEventLog.fileName),
                                  encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
        XCTAssertTrue(contents.contains("\"reason\":\"launch\""))
    }
}

final class DiagnosticsRedactionTests: XCTestCase {
    private func redacted(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(DiagnosticsRedaction.redactedSettings(Data(json.utf8)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testLocationValuesAreRemovedAtAnyDepth() throws {
        let out = try redacted(#"{"adaptiveLatitude":51.5,"clock":{"homeLongitude":-0.1,"minutes":30}}"#)
        XCTAssertEqual(out["adaptiveLatitude"] as? String, "<redacted>")
        let clock = try XCTUnwrap(out["clock"] as? [String: Any])
        XCTAssertEqual(clock["homeLongitude"] as? String, "<redacted>")
        XCTAssertEqual(clock["minutes"] as? Int, 30)
    }

    func testALocationFlagIsKeptBecauseItSaysNothingAboutWhere() throws {
        let out = try redacted(#"{"adaptiveLocationModeEnabled":true}"#)
        XCTAssertEqual(out["adaptiveLocationModeEnabled"] as? Bool, true)
    }

    func testAppPresetsAreReducedToACount() throws {
        let out = try redacted(#"{"appPresets":[{"bundleID":"com.example.a"},{"bundleID":"com.example.b"}]}"#)
        XCTAssertEqual(out["appPresets"] as? String, "<2 redacted>")
    }

    func testDisplayConfigurationPassesThroughUntouched() throws {
        let out = try redacted(#"{"osdEnabled":true,"displayGroups":[{"name":"Desk"}]}"#)
        XCTAssertEqual(out["osdEnabled"] as? Bool, true)
        XCTAssertEqual((out["displayGroups"] as? [[String: Any]])?.first?["name"] as? String, "Desk")
    }

    func testSomethingThatIsNotASettingsObjectYieldsNothing() {
        XCTAssertNil(DiagnosticsRedaction.redactedSettings(Data("[1,2]".utf8)))
    }
}
