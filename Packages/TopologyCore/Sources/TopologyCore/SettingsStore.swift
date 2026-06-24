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

    public init(
        persistencePolicy: PersistencePolicy = .reconnectOnQuit,
        confirmationCountdownSeconds: Int = 5,
        reconnectAllHotkeyEnabled: Bool = true,
        preventDisplaySleepWithExternal: Bool = false,
        autoDisconnectBuiltInOnExternal: Bool = false,
        arrangementAutoRevertSeconds: Int = 10,
        hotkeyShortcuts: KeyboardShortcutRegistry = .defaults
    ) {
        self.persistencePolicy = persistencePolicy
        self.confirmationCountdownSeconds = confirmationCountdownSeconds
        self.reconnectAllHotkeyEnabled = reconnectAllHotkeyEnabled
        self.preventDisplaySleepWithExternal = preventDisplaySleepWithExternal
        self.autoDisconnectBuiltInOnExternal = autoDisconnectBuiltInOnExternal
        self.arrangementAutoRevertSeconds = arrangementAutoRevertSeconds
        self.hotkeyShortcuts = hotkeyShortcuts
    }

    public static let `default` = OpenDisplaySettings()

    private enum CodingKeys: String, CodingKey {
        case persistencePolicy, confirmationCountdownSeconds, reconnectAllHotkeyEnabled
        case preventDisplaySleepWithExternal
        case autoDisconnectBuiltInOnExternal
        case arrangementAutoRevertSeconds
        case hotkeyShortcuts
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
