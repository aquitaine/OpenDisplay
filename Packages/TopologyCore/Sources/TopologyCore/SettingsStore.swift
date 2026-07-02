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
        publishOSDEventsEnabled: Bool = false
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
    }

    /// Tolerant decoder: every missing key falls back to its default and unknown keys are ignored,
    /// so settings files survive schema changes in either direction.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OpenDisplaySettings.default
        persistencePolicy = try container.decodeIfPresent(PersistencePolicy.self, forKey: .persistencePolicy)
            ?? defaults.persistencePolicy
        confirmationCountdownSeconds = try container.decodeIfPresent(Int.self, forKey: .confirmationCountdownSeconds)
            ?? defaults.confirmationCountdownSeconds
        reconnectAllHotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .reconnectAllHotkeyEnabled)
            ?? defaults.reconnectAllHotkeyEnabled
        preventDisplaySleepWithExternal = try container
            .decodeIfPresent(Bool.self, forKey: .preventDisplaySleepWithExternal)
            ?? defaults.preventDisplaySleepWithExternal
        autoDisconnectBuiltInOnExternal = try container
            .decodeIfPresent(Bool.self, forKey: .autoDisconnectBuiltInOnExternal)
            ?? defaults.autoDisconnectBuiltInOnExternal
        arrangementAutoRevertSeconds = try container
            .decodeIfPresent(Int.self, forKey: .arrangementAutoRevertSeconds)
            ?? defaults.arrangementAutoRevertSeconds
        hotkeyShortcuts = try container
            .decodeIfPresent(KeyboardShortcutRegistry.self, forKey: .hotkeyShortcuts)
            ?? defaults.hotkeyShortcuts
        displayNotificationsEnabled = try container
            .decodeIfPresent(Bool.self, forKey: .displayNotificationsEnabled)
            ?? defaults.displayNotificationsEnabled
        mediaKeyInterceptionEnabled = try container
            .decodeIfPresent(Bool.self, forKey: .mediaKeyInterceptionEnabled)
            ?? defaults.mediaKeyInterceptionEnabled
        mediaKeyTargetMode = try container
            .decodeIfPresent(MediaKeyTargetMode.self, forKey: .mediaKeyTargetMode)
            ?? defaults.mediaKeyTargetMode
        osdEnabled = try container.decodeIfPresent(Bool.self, forKey: .osdEnabled)
            ?? defaults.osdEnabled
        osdStyle = try container.decodeIfPresent(OSDStyle.self, forKey: .osdStyle)
            ?? defaults.osdStyle
        osdPosition = try container.decodeIfPresent(OSDPosition.self, forKey: .osdPosition)
            ?? defaults.osdPosition
        publishOSDEventsEnabled = try container
            .decodeIfPresent(Bool.self, forKey: .publishOSDEventsEnabled)
            ?? defaults.publishOSDEventsEnabled
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
