import DisplayDomain
import Foundation

/// User-tunable app settings persisted as JSON (PRD §10.8 SettingsStore). Kept small, Codable, and
/// versioned-by-tolerance: unknown keys are ignored and missing keys fall back to the defaults, so
/// older/newer settings files load without error.
public struct OpenDisplaySettings: Hashable, Sendable, Codable {
    /// Default reconnect behavior applied to managed-offline displays (D-005).
    public var persistencePolicy: PersistencePolicy
    /// Countdown shown before a confirmed (risky) disconnect proceeds (LIF-006).
    public var confirmationCountdownSeconds: Int
    /// Whether the global Reconnect-All hotkey is registered.
    public var reconnectAllHotkeyEnabled: Bool
    /// When on, hold a "prevent display idle-sleep" power assertion while ≥1 external display is
    /// present, so the Mac doesn't dim/sleep its screens during a presentation or always-on setup.
    public var preventDisplaySleepWithExternal: Bool
    /// When on, turn the built-in panel off automatically the moment an external display arrives
    /// (Issue 5 — the clamshell-style original use case). The built-in returns when the last external
    /// leaves (via the always-one-active safety net).
    public var autoDisconnectBuiltInOnExternal: Bool
    /// Seconds the "Keep these display settings?" prompt waits before auto-reverting a
    /// resolution/mirror/set-main change (Issue 6). Floored at 3 by the app.
    public var arrangementAutoRevertSeconds: Int
    /// Configurable global keyboard shortcuts (Batch-2 #4). Defaults to the shipped bindings.
    public var hotkeyShortcuts: KeyboardShortcutRegistry
    /// When on, post a user notification on display connect/disconnect and related events (Batch-2 #5).
    public var displayNotificationsEnabled: Bool
    /// When on, intercept the hardware brightness/volume media keys and route them to the target
    /// display (Batch-3 #3). Requires the Accessibility permission; default off so a user who never
    /// enables it is never prompted.
    public var mediaKeyInterceptionEnabled: Bool
    /// Which display the media keys act on (Batch-3 #1/#3).
    public var mediaKeyTargetMode: MediaKeyTargetMode
    /// When on, show the on-screen-display HUD for brightness/volume changes (Batch-3 #4). Independent
    /// of media keys — the HUD also fires for menu/CLI/Intent-driven changes.
    public var osdEnabled: Bool
    /// The OSD HUD's visual style (Batch-3 #5).
    public var osdStyle: OSDStyle
    /// Where the OSD HUD appears on the target display (Batch-3 #5).
    public var osdPosition: OSDPosition
    /// When on, broadcast each OSD event over `DistributedNotificationCenter` for external/notch HUD
    /// apps (Batch-3 #6). Default off.
    public var publishOSDEventsEnabled: Bool
    /// FaceLight restore ledger, keyed by `DisplayRecordID.rawValue`: each display's brightness/
    /// contrast at the moment FaceLight turned it into a fill light. INVARIANT: a key is present if
    /// and only if FaceLight is currently active for that display and a restore is owed; persisted
    /// BEFORE the max-brightness write and cleared after every restore, so a crash/relaunch
    /// mid-FaceLight still restores correctly (mirrors `adaptiveDayPresetByDisplay`).
    public var faceLightPriorStateByDisplay: [String: FaceLightPolicy.PriorState]
    /// Adaptive Display (Labs): mirror the built-in panel's (ambient-light-driven) brightness to
    /// external displays' hardware backlight over DDC; falls back to the schedule curve below when
    /// no built-in is active (clamshell). Default off.
    public var adaptiveBrightnessSyncEnabled: Bool
    /// Adaptive Display (Labs): switch external displays' hardware colour preset (VCP 0x14) to a
    /// warm preset in the evening and back in the morning. Follows macOS Night Shift's live state
    /// when readable; otherwise the schedule below. Default off.
    public var adaptiveWarmthEnabled: Bool
    /// Minute-of-day the adaptive "day" phase begins (default 420 = 07:00).
    public var adaptiveDayStartMinute: Int
    /// Minute-of-day the adaptive "night" phase begins (default 1140 = 19:00).
    public var adaptiveNightStartMinute: Int
    /// Width in minutes of the linear brightness ramp at each schedule edge (default 30).
    public var adaptiveTransitionMinutes: Int
    /// Schedule-fallback brightness during the day phase, 0...1 (default 0.8).
    public var adaptiveFallbackDayLevel: Float
    /// Schedule-fallback brightness during the night phase, 0...1 (default 0.35).
    public var adaptiveFallbackNightLevel: Float
    /// Colour-preset code applied in the evening (MCCS 0x14; default 4 = 5000 K — mild warmth).
    public var adaptiveEveningPreset: Int
    /// Day-preset memory, keyed by `DisplayRecordID.rawValue` (String keys — raw-representable
    /// dictionary keys encode as flat arrays in JSON). INVARIANT: a key is present if and only if
    /// an evening preset is currently applied and a day restore is owed; persisted BEFORE the
    /// evening write and cleared after every restore, so a crash/relaunch mid-evening still
    /// restores correctly and never re-captures the warm preset as "day".
    public var adaptiveDayPresetByDisplay: [String: Int]
    /// Learned brightness offsets (user's manual tweak relative to the built-in), keyed by
    /// `DisplayRecordID.rawValue`; survives relaunch so sync resumes at the user's preference.
    public var adaptiveBrightnessOffsetByDisplay: [String: Float]
    /// Adaptive Display (Labs) — Location Mode (Issue #31): drive brightness from the sun's
    /// elevation at `clockManualLocation`, a better lid-closed fallback than the flat schedule.
    /// Ranks below the built-in mirror and the ambient sensor (both outrank it when available) but
    /// above the flat day/night schedule; Clock Mode's `clockScheduleEnabled` still outranks all of
    /// them. Default off. No location configured ⇒ degrades to the flat schedule like today.
    public var adaptiveLocationModeEnabled: Bool
    /// Clock Mode (Issue #30): apply a user-authored brightness schedule to external displays. Each
    /// entry is time- or solar-anchored with a per-anchor minute offset and a transition style.
    /// Default off. When on, Clock Mode's scheduled brightness takes precedence over Adaptive
    /// Display's built-in mirror (an explicit schedule outranks the inferred sync); Adaptive warmth
    /// is orthogonal and unaffected.
    public var clockScheduleEnabled: Bool
    /// The Clock Mode schedule entries applied to every external display (shared schedule).
    public var clockScheduleEntries: [ClockScheduleEntry]
    /// Manual location for solar anchors (sunrise/noon/sunset) and for Location Mode's elevation
    /// curve, the fallback when CoreLocation is unavailable. Nil ⇒ solar-anchored schedule entries
    /// are skipped and Location Mode degrades to the flat schedule; time anchors always work.
    public var clockManualLocation: GeoCoordinate?
    /// When on, ask GitHub for the newest release at most once a day and surface it in the menu.
    /// Manual "Check for updates" works regardless. Nothing is ever downloaded automatically.
    public var updateCheckEnabled: Bool
    /// How the software dimming slider darkens a display (gamma table, overlay window, or both).
    public var dimmingMethod: DimmingMethod
    /// App Presets (Issue #33): switch a display's brightness/contrast/colour preset when a chosen app
    /// becomes frontmost and restore the prior state when it leaves. Default off.
    public var appPresetsEnabled: Bool
    /// The configured per-app presets (at most one per bundle identifier).
    public var appPresets: [AppPresetPolicy.AppPreset]
    /// App-preset restore ledger, keyed by `DisplayRecordID.rawValue`: each governed display's
    /// brightness/contrast/colour-preset at the moment its app preset took over. INVARIANT: a key is
    /// present if and only if an app preset is currently applied to that display and a restore is
    /// owed; captured BEFORE the preset write and cleared after every restore, so a crash/relaunch
    /// mid-preset still restores correctly (mirrors `faceLightPriorStateByDisplay`).
    public var appPresetPriorStateByDisplay: [String: AppPresetPolicy.PriorState]

    public init(
        persistencePolicy: PersistencePolicy = .reconnectOnQuit,
        confirmationCountdownSeconds: Int = 5,
        reconnectAllHotkeyEnabled: Bool = true,
        preventDisplaySleepWithExternal: Bool = false,
        autoDisconnectBuiltInOnExternal: Bool = false,
        arrangementAutoRevertSeconds: Int = 10,
        hotkeyShortcuts: KeyboardShortcutRegistry = .defaults,
        displayNotificationsEnabled: Bool = false,
        mediaKeyInterceptionEnabled: Bool = false,
        mediaKeyTargetMode: MediaKeyTargetMode = .underCursor,
        osdEnabled: Bool = true,
        osdStyle: OSDStyle = .native,
        osdPosition: OSDPosition = .bottomCenter,
        publishOSDEventsEnabled: Bool = false,
        faceLightPriorStateByDisplay: [String: FaceLightPolicy.PriorState] = [:],
        adaptiveBrightnessSyncEnabled: Bool = false,
        adaptiveWarmthEnabled: Bool = false,
        adaptiveDayStartMinute: Int = 420,
        adaptiveNightStartMinute: Int = 1140,
        adaptiveTransitionMinutes: Int = 30,
        adaptiveFallbackDayLevel: Float = 0.8,
        adaptiveFallbackNightLevel: Float = 0.35,
        adaptiveEveningPreset: Int = 4,
        adaptiveDayPresetByDisplay: [String: Int] = [:],
        adaptiveBrightnessOffsetByDisplay: [String: Float] = [:],
        adaptiveLocationModeEnabled: Bool = false,
        clockScheduleEnabled: Bool = false,
        clockScheduleEntries: [ClockScheduleEntry] = [],
        clockManualLocation: GeoCoordinate? = nil,
        updateCheckEnabled: Bool = true,
        dimmingMethod: DimmingMethod = .gamma,
        appPresetsEnabled: Bool = false,
        appPresets: [AppPresetPolicy.AppPreset] = [],
        appPresetPriorStateByDisplay: [String: AppPresetPolicy.PriorState] = [:]
    ) {
        self.persistencePolicy = persistencePolicy
        self.confirmationCountdownSeconds = confirmationCountdownSeconds
        self.reconnectAllHotkeyEnabled = reconnectAllHotkeyEnabled
        self.preventDisplaySleepWithExternal = preventDisplaySleepWithExternal
        self.autoDisconnectBuiltInOnExternal = autoDisconnectBuiltInOnExternal
        self.arrangementAutoRevertSeconds = arrangementAutoRevertSeconds
        self.hotkeyShortcuts = hotkeyShortcuts
        self.displayNotificationsEnabled = displayNotificationsEnabled
        self.mediaKeyInterceptionEnabled = mediaKeyInterceptionEnabled
        self.mediaKeyTargetMode = mediaKeyTargetMode
        self.osdEnabled = osdEnabled
        self.osdStyle = osdStyle
        self.osdPosition = osdPosition
        self.publishOSDEventsEnabled = publishOSDEventsEnabled
        self.faceLightPriorStateByDisplay = faceLightPriorStateByDisplay
        self.adaptiveBrightnessSyncEnabled = adaptiveBrightnessSyncEnabled
        self.adaptiveWarmthEnabled = adaptiveWarmthEnabled
        self.adaptiveDayStartMinute = adaptiveDayStartMinute
        self.adaptiveNightStartMinute = adaptiveNightStartMinute
        self.adaptiveTransitionMinutes = adaptiveTransitionMinutes
        self.adaptiveFallbackDayLevel = adaptiveFallbackDayLevel
        self.adaptiveFallbackNightLevel = adaptiveFallbackNightLevel
        self.adaptiveEveningPreset = adaptiveEveningPreset
        self.adaptiveDayPresetByDisplay = adaptiveDayPresetByDisplay
        self.adaptiveBrightnessOffsetByDisplay = adaptiveBrightnessOffsetByDisplay
        self.adaptiveLocationModeEnabled = adaptiveLocationModeEnabled
        self.clockScheduleEnabled = clockScheduleEnabled
        self.clockScheduleEntries = clockScheduleEntries
        self.clockManualLocation = clockManualLocation
        self.updateCheckEnabled = updateCheckEnabled
        self.dimmingMethod = dimmingMethod
        self.appPresetsEnabled = appPresetsEnabled
        self.appPresets = appPresets
        self.appPresetPriorStateByDisplay = appPresetPriorStateByDisplay
    }

    public static let `default` = OpenDisplaySettings()

    private enum CodingKeys: String, CodingKey {
        case persistencePolicy, confirmationCountdownSeconds, reconnectAllHotkeyEnabled
        case preventDisplaySleepWithExternal
        case autoDisconnectBuiltInOnExternal
        case arrangementAutoRevertSeconds
        case hotkeyShortcuts
        case displayNotificationsEnabled
        case mediaKeyInterceptionEnabled
        case mediaKeyTargetMode
        case osdEnabled
        case osdStyle
        case osdPosition
        case publishOSDEventsEnabled
        case faceLightPriorStateByDisplay
        case adaptiveBrightnessSyncEnabled
        case adaptiveWarmthEnabled
        case adaptiveDayStartMinute
        case adaptiveNightStartMinute
        case adaptiveTransitionMinutes
        case adaptiveFallbackDayLevel
        case adaptiveFallbackNightLevel
        case adaptiveEveningPreset
        case adaptiveDayPresetByDisplay
        case adaptiveBrightnessOffsetByDisplay
        case adaptiveLocationModeEnabled
        case clockScheduleEnabled
        case clockScheduleEntries
        case clockManualLocation
        case updateCheckEnabled
        case dimmingMethod
        case appPresetsEnabled
        case appPresets
        case appPresetPriorStateByDisplay
    }

    /// Tolerant decoder: every missing OR undecodable key falls back to its default and unknown
    /// keys are ignored, so settings files survive schema changes in either direction. Per-key
    /// tolerance matters as much as missing-key tolerance: one unknown enum case or reshaped field
    /// (e.g. after a downgrade) must degrade that one setting, not throw the whole file away —
    /// `load()` would return `.default` and the next save would overwrite every setting *and* the
    /// FaceLight/app-preset/day-preset restore ledgers, stranding displays at applied values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OpenDisplaySettings.default
        persistencePolicy = container.lenient(PersistencePolicy.self, forKey: .persistencePolicy)
            ?? defaults.persistencePolicy
        confirmationCountdownSeconds = container.lenient(Int.self, forKey: .confirmationCountdownSeconds)
            ?? defaults.confirmationCountdownSeconds
        reconnectAllHotkeyEnabled = container.lenient(Bool.self, forKey: .reconnectAllHotkeyEnabled)
            ?? defaults.reconnectAllHotkeyEnabled
        preventDisplaySleepWithExternal = container.lenient(Bool.self, forKey: .preventDisplaySleepWithExternal)
            ?? defaults.preventDisplaySleepWithExternal
        autoDisconnectBuiltInOnExternal = container.lenient(Bool.self, forKey: .autoDisconnectBuiltInOnExternal)
            ?? defaults.autoDisconnectBuiltInOnExternal
        arrangementAutoRevertSeconds = container.lenient(Int.self, forKey: .arrangementAutoRevertSeconds)
            ?? defaults.arrangementAutoRevertSeconds
        hotkeyShortcuts = container.lenient(KeyboardShortcutRegistry.self, forKey: .hotkeyShortcuts)
            ?? defaults.hotkeyShortcuts
        displayNotificationsEnabled = container.lenient(Bool.self, forKey: .displayNotificationsEnabled)
            ?? defaults.displayNotificationsEnabled
        mediaKeyInterceptionEnabled = container.lenient(Bool.self, forKey: .mediaKeyInterceptionEnabled)
            ?? defaults.mediaKeyInterceptionEnabled
        mediaKeyTargetMode = container.lenient(MediaKeyTargetMode.self, forKey: .mediaKeyTargetMode)
            ?? defaults.mediaKeyTargetMode
        osdEnabled = container.lenient(Bool.self, forKey: .osdEnabled)
            ?? defaults.osdEnabled
        osdStyle = container.lenient(OSDStyle.self, forKey: .osdStyle)
            ?? defaults.osdStyle
        osdPosition = container.lenient(OSDPosition.self, forKey: .osdPosition)
            ?? defaults.osdPosition
        publishOSDEventsEnabled = container.lenient(Bool.self, forKey: .publishOSDEventsEnabled)
            ?? defaults.publishOSDEventsEnabled
        faceLightPriorStateByDisplay = container.lenient([String: FaceLightPolicy.PriorState].self, forKey: .faceLightPriorStateByDisplay)
            ?? defaults.faceLightPriorStateByDisplay
        adaptiveBrightnessSyncEnabled = container.lenient(Bool.self, forKey: .adaptiveBrightnessSyncEnabled)
            ?? defaults.adaptiveBrightnessSyncEnabled
        adaptiveWarmthEnabled = container.lenient(Bool.self, forKey: .adaptiveWarmthEnabled)
            ?? defaults.adaptiveWarmthEnabled
        adaptiveDayStartMinute = container.lenient(Int.self, forKey: .adaptiveDayStartMinute)
            ?? defaults.adaptiveDayStartMinute
        adaptiveNightStartMinute = container.lenient(Int.self, forKey: .adaptiveNightStartMinute)
            ?? defaults.adaptiveNightStartMinute
        adaptiveTransitionMinutes = container.lenient(Int.self, forKey: .adaptiveTransitionMinutes)
            ?? defaults.adaptiveTransitionMinutes
        adaptiveFallbackDayLevel = container.lenient(Float.self, forKey: .adaptiveFallbackDayLevel)
            ?? defaults.adaptiveFallbackDayLevel
        adaptiveFallbackNightLevel = container.lenient(Float.self, forKey: .adaptiveFallbackNightLevel)
            ?? defaults.adaptiveFallbackNightLevel
        adaptiveEveningPreset = container.lenient(Int.self, forKey: .adaptiveEveningPreset)
            ?? defaults.adaptiveEveningPreset
        adaptiveDayPresetByDisplay = container.lenient([String: Int].self, forKey: .adaptiveDayPresetByDisplay)
            ?? defaults.adaptiveDayPresetByDisplay
        adaptiveBrightnessOffsetByDisplay = container.lenient([String: Float].self, forKey: .adaptiveBrightnessOffsetByDisplay)
            ?? defaults.adaptiveBrightnessOffsetByDisplay
        adaptiveLocationModeEnabled = container.lenient(Bool.self, forKey: .adaptiveLocationModeEnabled)
            ?? defaults.adaptiveLocationModeEnabled
        clockScheduleEnabled = container.lenient(Bool.self, forKey: .clockScheduleEnabled)
            ?? defaults.clockScheduleEnabled
        clockScheduleEntries = container.lenient([ClockScheduleEntry].self, forKey: .clockScheduleEntries)
            ?? defaults.clockScheduleEntries
        clockManualLocation = container.lenient(GeoCoordinate.self, forKey: .clockManualLocation)
            ?? defaults.clockManualLocation
        updateCheckEnabled = container.lenient(Bool.self, forKey: .updateCheckEnabled)
            ?? defaults.updateCheckEnabled
        dimmingMethod = container.lenient(DimmingMethod.self, forKey: .dimmingMethod)
            ?? defaults.dimmingMethod
        appPresetsEnabled = container.lenient(Bool.self, forKey: .appPresetsEnabled)
            ?? defaults.appPresetsEnabled
        appPresets = container.lenient([AppPresetPolicy.AppPreset].self, forKey: .appPresets)
            ?? defaults.appPresets
        appPresetPriorStateByDisplay = container.lenient([String: AppPresetPolicy.PriorState].self,
                             forKey: .appPresetPriorStateByDisplay)
            ?? defaults.appPresetPriorStateByDisplay
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` that also tolerates a present-but-undecodable value, returning nil instead
    /// of throwing — the per-key half of `OpenDisplaySettings`' tolerant decoding.
    fileprivate func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Atomic, on-disk store for `OpenDisplaySettings`. Pure Foundation, so it lives in the
/// cross-platform core and is exercised by `make test`; the app points it at Application Support.
public struct SettingsStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("settings.json")
    }

    /// The shared Application Support location (same folder the checkpoints use).
    public static func defaultDirectory(
        appName: String = "OpenDisplay",
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    /// Returns persisted settings, or `.default` when the file is absent or unreadable — so first
    /// run and a corrupt file both degrade to sane defaults instead of failing.
    public func load() -> OpenDisplaySettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(OpenDisplaySettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public func save(_ settings: OpenDisplaySettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
