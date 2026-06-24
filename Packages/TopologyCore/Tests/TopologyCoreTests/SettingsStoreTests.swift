import XCTest
import DisplayDomain
@testable import TopologyCore

final class SettingsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-settings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadReturnsDefaultsWhenAbsent() {
        let store = SettingsStore(directory: directory)
        XCTAssertEqual(store.load(), .default)
        XCTAssertEqual(store.load().persistencePolicy, .reconnectOnQuit)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = SettingsStore(directory: directory)
        let settings = OpenDisplaySettings(
            persistencePolicy: .persistentOffline,
            confirmationCountdownSeconds: 12,
            reconnectAllHotkeyEnabled: false
        )
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let store = SettingsStore(directory: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.load(), .default)
    }

    func testUnknownKeysAndMissingKeysTolerated() throws {
        // A file with an extra key and a missing key should still load, using defaults for the gaps.
        let json = #"{"persistencePolicy":"reconnectOnWake","futureKey":42}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings.json"))
        let loaded = SettingsStore(directory: directory).load()
        XCTAssertEqual(loaded.persistencePolicy, .reconnectOnWake)
        XCTAssertEqual(loaded.confirmationCountdownSeconds, OpenDisplaySettings.default.confirmationCountdownSeconds)
    }

    func testPreventDisplaySleepDefaultsOffAndRoundTrips() throws {
        XCTAssertFalse(OpenDisplaySettings.default.preventDisplaySleepWithExternal)
        let store = SettingsStore(directory: directory)
        let settings = OpenDisplaySettings(preventDisplaySleepWithExternal: true)
        try store.save(settings)
        XCTAssertTrue(store.load().preventDisplaySleepWithExternal)
    }

    func testMissingPreventDisplaySleepKeyDefaultsOff() throws {
        // A settings file written before this key existed must still load, defaulting the key off.
        let json = #"{"persistencePolicy":"reconnectOnQuit","confirmationCountdownSeconds":5}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertFalse(SettingsStore(directory: directory).load().preventDisplaySleepWithExternal)
    }

    func testArrangementAutoRevertDefaultsTo10AndRoundTrips() throws {
        XCTAssertEqual(OpenDisplaySettings.default.arrangementAutoRevertSeconds, 10)
        let store = SettingsStore(directory: directory)
        try store.save(OpenDisplaySettings(arrangementAutoRevertSeconds: 15))
        XCTAssertEqual(store.load().arrangementAutoRevertSeconds, 15)
        // A file from before this key existed defaults to 10.
        try Data(#"{"persistencePolicy":"reconnectOnQuit","confirmationCountdownSeconds":5}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(SettingsStore(directory: directory).load().arrangementAutoRevertSeconds, 10)
    }

    func testAutoDisconnectBuiltInDefaultsOffAndRoundTrips() throws {
        XCTAssertFalse(OpenDisplaySettings.default.autoDisconnectBuiltInOnExternal)
        let store = SettingsStore(directory: directory)
        try store.save(OpenDisplaySettings(autoDisconnectBuiltInOnExternal: true))
        XCTAssertTrue(store.load().autoDisconnectBuiltInOnExternal)
        // Missing key in an older file defaults off.
        try Data(#"{"persistencePolicy":"reconnectOnQuit"}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertFalse(SettingsStore(directory: directory).load().autoDisconnectBuiltInOnExternal)
    }

    func testSettingsFileIsIndependentlyReadable() throws {
        let store = SettingsStore(directory: directory)
        try store.save(OpenDisplaySettings(persistencePolicy: .reconnectOnWake))
        let data = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
        let decoded = try JSONDecoder().decode(OpenDisplaySettings.self, from: data)
        XCTAssertEqual(decoded.persistencePolicy, .reconnectOnWake)
    }
}
