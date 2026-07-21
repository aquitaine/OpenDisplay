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

    func testAppPresetsAndTheirRestoreLedgerSurviveSaveAndLoad() throws {
        let store = SettingsStore(directory: directory)
        let preset = AppPresetPolicy.AppPreset(
            bundleIdentifier: "com.figma.Desktop", applicationName: "Figma",
            brightness: 0.6, colorPreset: 4, target: .display("cgid:1"))
        let settings = OpenDisplaySettings(
            appPresetsEnabled: true, appPresets: [preset],
            appPresetPriorStateByDisplay: ["cgid:1": AppPresetPolicy.PriorState(brightness: 0.9)])
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.appPresets, [preset])
        XCTAssertEqual(loaded.appPresetPriorStateByDisplay["cgid:1"],
                       AppPresetPolicy.PriorState(brightness: 0.9))
    }

    func testAppPresetFieldsDefaultWhenAbsentFromAnOlderFile() throws {
        let store = SettingsStore(directory: directory)
        try Data(#"{"confirmationCountdownSeconds": 7}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        let loaded = store.load()
        XCTAssertFalse(loaded.appPresetsEnabled)
        XCTAssertTrue(loaded.appPresets.isEmpty)
        XCTAssertTrue(loaded.appPresetPriorStateByDisplay.isEmpty)
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

    func testAdaptiveFieldsDefaultOffAndRoundTrip() throws {
        // Both behaviors default OFF (opt-in Labs feature); tunables have sane defaults.
        let defaults = OpenDisplaySettings.default
        XCTAssertFalse(defaults.adaptiveBrightnessSyncEnabled)
        XCTAssertFalse(defaults.adaptiveWarmthEnabled)
        XCTAssertEqual(defaults.adaptiveDayStartMinute, 420)
        XCTAssertEqual(defaults.adaptiveNightStartMinute, 1140)
        XCTAssertEqual(defaults.adaptiveEveningPreset, 4)
        XCTAssertTrue(defaults.adaptiveDayPresetByDisplay.isEmpty)

        let store = SettingsStore(directory: directory)
        let settings = OpenDisplaySettings(
            adaptiveBrightnessSyncEnabled: true,
            adaptiveWarmthEnabled: true,
            adaptiveNightStartMinute: 1200,
            adaptiveEveningPreset: 3,
            adaptiveDayPresetByDisplay: ["cg:abc": 2],
            adaptiveBrightnessOffsetByDisplay: ["cg:abc": -0.15]
        )
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testPreAdaptiveSettingsFileDecodesToAdaptiveDefaults() throws {
        // A 0.3.0-era settings file (no adaptive keys) must load with the user's values intact
        // and every adaptive field at its default — never fall back to .default wholesale.
        let json = #"{"persistencePolicy":"persistentOffline","mediaKeyInterceptionEnabled":true}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings.json"))
        let loaded = SettingsStore(directory: directory).load()
        XCTAssertEqual(loaded.persistencePolicy, .persistentOffline)
        XCTAssertTrue(loaded.mediaKeyInterceptionEnabled)
        XCTAssertFalse(loaded.adaptiveBrightnessSyncEnabled)
        XCTAssertEqual(loaded.adaptiveEveningPreset, 4)
        XCTAssertTrue(loaded.adaptiveBrightnessOffsetByDisplay.isEmpty)
    }

    func testClockScheduleFieldsDefaultOffAndRoundTrip() throws {
        let defaults = OpenDisplaySettings.default
        XCTAssertFalse(defaults.clockScheduleEnabled)
        XCTAssertTrue(defaults.clockScheduleEntries.isEmpty)
        XCTAssertNil(defaults.clockManualLocation)

        let store = SettingsStore(directory: directory)
        let entry = ClockScheduleEntry(anchor: .sunrise, offsetMinutes: -30, brightness: 0.7,
                                       transition: .ramp)
        let settings = OpenDisplaySettings(
            clockScheduleEnabled: true,
            clockScheduleEntries: [entry,
                                   ClockScheduleEntry(anchor: .time, timeMinute: 1320, brightness: 0.3,
                                                      transition: .instant)],
            clockManualLocation: GeoCoordinate(latitude: 51.4769, longitude: 0.0))
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(store.load().clockScheduleEntries.first, entry)
    }

    func testPreClockSettingsFileDecodesToClockDefaults() throws {
        // A settings file from before Clock Mode existed loads with the user's values intact and the
        // clock fields at their defaults — never a wholesale fall back to .default.
        let json = #"{"persistencePolicy":"persistentOffline","adaptiveWarmthEnabled":true}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings.json"))
        let loaded = SettingsStore(directory: directory).load()
        XCTAssertEqual(loaded.persistencePolicy, .persistentOffline)
        XCTAssertTrue(loaded.adaptiveWarmthEnabled)
        XCTAssertFalse(loaded.clockScheduleEnabled)
        XCTAssertTrue(loaded.clockScheduleEntries.isEmpty)
        XCTAssertNil(loaded.clockManualLocation)
    }

    func testDisplayNotificationsDefaultsOffAndRoundTrips() throws {
        XCTAssertFalse(OpenDisplaySettings.default.displayNotificationsEnabled)
        let store = SettingsStore(directory: directory)
        try store.save(OpenDisplaySettings(displayNotificationsEnabled: true))
        XCTAssertTrue(store.load().displayNotificationsEnabled)
        try Data(#"{"persistencePolicy":"reconnectOnQuit"}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertFalse(SettingsStore(directory: directory).load().displayNotificationsEnabled)
    }

    func testHotkeyShortcutsDefaultAndRoundTrip() throws {
        XCTAssertEqual(OpenDisplaySettings.default.hotkeyShortcuts, .defaults)
        let store = SettingsStore(directory: directory)
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(KeyBinding(keyCode: 0x7E, modifiers: KeyBinding.controlOptionCommand), for: .brightnessUp)
        try store.save(OpenDisplaySettings(hotkeyShortcuts: reg))
        XCTAssertEqual(store.load().hotkeyShortcuts, reg)
        // Older file without the key → defaults.
        try Data(#"{"persistencePolicy":"reconnectOnQuit"}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(SettingsStore(directory: directory).load().hotkeyShortcuts, .defaults)
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

    func testMediaKeyAndOSDDefaultsAndRoundTrip() throws {
        // Batch-3 defaults: media keys off, OSD on, native style, bottom-center, broadcast off.
        let defaults = OpenDisplaySettings.default
        XCTAssertFalse(defaults.mediaKeyInterceptionEnabled)
        XCTAssertEqual(defaults.mediaKeyTargetMode, .underCursor)
        XCTAssertTrue(defaults.osdEnabled)
        XCTAssertEqual(defaults.osdStyle, .native)
        XCTAssertEqual(defaults.osdPosition, .bottomCenter)
        XCTAssertFalse(defaults.publishOSDEventsEnabled)

        let store = SettingsStore(directory: directory)
        let settings = OpenDisplaySettings(
            mediaKeyInterceptionEnabled: true,
            mediaKeyTargetMode: .mainDisplay,
            osdEnabled: false,
            osdStyle: .minimal,
            osdPosition: .topCenter,
            publishOSDEventsEnabled: true
        )
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)

        // A settings file from before these keys existed loads with all Batch-3 defaults.
        try Data(#"{"persistencePolicy":"reconnectOnQuit"}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        let loaded = SettingsStore(directory: directory).load()
        XCTAssertFalse(loaded.mediaKeyInterceptionEnabled)
        XCTAssertEqual(loaded.mediaKeyTargetMode, .underCursor)
        XCTAssertTrue(loaded.osdEnabled)
        XCTAssertEqual(loaded.osdStyle, .native)
    }

    func testFaceLightLedgerDefaultsEmptyAndRoundTrips() throws {
        XCTAssertTrue(OpenDisplaySettings.default.faceLightPriorStateByDisplay.isEmpty)
        let store = SettingsStore(directory: directory)
        let settings = OpenDisplaySettings(
            faceLightPriorStateByDisplay: ["cg:abc": FaceLightPolicy.PriorState(brightness: 0.4, contrast: 0.5)]
        )
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testPreFaceLightSettingsFileDecodesToEmptyLedger() throws {
        // A settings file from before FaceLight existed must still load, defaulting the ledger empty
        // rather than losing the rest of the file's values.
        let json = #"{"persistencePolicy":"persistentOffline","mediaKeyInterceptionEnabled":true}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings.json"))
        let loaded = SettingsStore(directory: directory).load()
        XCTAssertEqual(loaded.persistencePolicy, .persistentOffline)
        XCTAssertTrue(loaded.mediaKeyInterceptionEnabled)
        XCTAssertTrue(loaded.faceLightPriorStateByDisplay.isEmpty)
    }

    func testSettingsFileIsIndependentlyReadable() throws {
        let store = SettingsStore(directory: directory)
        try store.save(OpenDisplaySettings(persistencePolicy: .reconnectOnWake))
        let data = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
        let decoded = try JSONDecoder().decode(OpenDisplaySettings.self, from: data)
        XCTAssertEqual(decoded.persistencePolicy, .reconnectOnWake)
    }
}
