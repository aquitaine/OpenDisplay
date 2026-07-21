import Foundation

/// One line of `opendisplay listen`'s line-delimited JSON output (Issue #34). `version` and `event`
/// are on every line; the remaining keys are present only when that `event` kind sets them (Swift's
/// `Codable` synthesis omits `nil` optionals rather than writing `null`), so a consumer switches on
/// `event` and reads the keys that kind defines:
///
///     {"version":1,"event":"brightness","timestamp":1737482921.5,"displayId":"cg:abc",
///      "displayName":"Studio Display","level":0.62,"source":"mediaKey"}
///     {"version":1,"event":"config","timestamp":1737482925.0,
///      "displays":[{"id":"cg:abc","active":true,"main":true,"mode":"3840x2160@60"}]}
///
/// `brightness` mirrors a live `OSDBroadcast` (menu/media-key/CLI/App-Intent origin, brightness kind
/// only — volume/mute are a future line kind, not emitted today). `config` fires whenever the display
/// topology changes (hotplug, mode, rotation, mirror, main display) and carries a compact snapshot so
/// most scripts never need a follow-up `list` call.
public struct ListenEvent: Hashable, Sendable, Codable {
    /// Current schema version (bump on any breaking field change).
    public static let schemaVersion = 1

    public enum Kind: String, Hashable, Sendable, Codable {
        case brightness
        case config
    }

    /// One display's status inside a `config` event.
    public struct DisplaySummary: Hashable, Sendable, Codable {
        public var id: String
        public var active: Bool
        public var main: Bool
        public var mode: String?

        public init(id: String, active: Bool, main: Bool, mode: String?) {
            self.id = id
            self.active = active
            self.main = main
            self.mode = mode
        }
    }

    public var version: Int
    public var event: Kind
    public var timestamp: Double
    public var displayId: String?
    public var displayName: String?
    public var level: Double?
    public var source: String?
    public var displays: [DisplaySummary]?

    public init(
        event: Kind, timestamp: Double, displayId: String? = nil, displayName: String? = nil,
        level: Double? = nil, source: String? = nil, displays: [DisplaySummary]? = nil
    ) {
        self.version = Self.schemaVersion
        self.event = event
        self.timestamp = timestamp
        self.displayId = displayId
        self.displayName = displayName
        self.level = level
        self.source = source
        self.displays = displays
    }

    /// A `brightness` line mirroring a live `OSDBroadcast`.
    public static func brightness(from broadcast: OSDBroadcast) -> ListenEvent {
        ListenEvent(
            event: .brightness, timestamp: broadcast.timestamp, displayId: broadcast.displayID,
            displayName: broadcast.displayName, level: broadcast.value, source: broadcast.source)
    }

    /// A `config` line: the topology changed (hotplug, mode, rotation, mirror, main display).
    public static func config(at timestamp: Double, displays: [DisplaySummary]) -> ListenEvent {
        ListenEvent(event: .config, timestamp: timestamp, displays: displays)
    }
}
