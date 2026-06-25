import Foundation

/// A stable, cross-process payload describing one OSD event (Batch-3 #6), published over
/// `DistributedNotificationCenter` so external/notch HUD apps can render OpenDisplay's brightness/
/// volume changes. Versioned and tolerant, like `URLCommand` and `DDCPowerMode`.
public struct OSDBroadcast: Hashable, Sendable, Codable {
    /// Current schema version (bump on any breaking field change).
    public static let schemaVersion = 1
    /// The `DistributedNotificationCenter` name subscribers listen on.
    public static let notificationName = "dev.opendisplay.osd"

    public enum Kind: String, Hashable, Sendable, Codable {
        case brightness
        case volume
        case mute
    }

    public var version: Int
    public var kind: Kind
    /// Normalized level, clamped to 0...1.
    public var value: Double
    /// The display's stable record id.
    public var displayID: String
    /// The display's user-facing name, when known.
    public var displayName: String?
    /// Where the change came from ("mediaKey" | "menu" | "cli" | "appIntent").
    public var source: String
    /// Seconds since 1970 (kept numeric so the dictionary form stays plist/string-clean).
    public var timestamp: Double

    public init(
        kind: Kind,
        value: Double,
        displayID: String,
        displayName: String? = nil,
        source: String,
        timestamp: Double
    ) {
        self.version = Self.schemaVersion
        self.kind = kind
        self.value = Swift.max(0, Swift.min(1, value))
        self.displayID = displayID
        self.displayName = displayName
        self.source = source
        self.timestamp = timestamp
    }

    /// String-only dictionary for `DistributedNotificationCenter` userInfo (cross-process safe).
    public var userInfo: [String: String] {
        var info: [String: String] = [
            "version": String(version),
            "kind": kind.rawValue,
            "value": String(value),
            "displayID": displayID,
            "source": source,
            "timestamp": String(timestamp),
        ]
        if let displayName { info["displayName"] = displayName }
        return info
    }

    /// Reconstruct from a distributed-notification userInfo dictionary. Tolerant: a missing required
    /// field returns nil; unknown extra keys are ignored; an out-of-range value is clamped.
    public init?(userInfo: [String: String]) {
        guard let kindRaw = userInfo["kind"], let kind = Kind(rawValue: kindRaw),
              let valueRaw = userInfo["value"], let value = Double(valueRaw),
              let displayID = userInfo["displayID"], !displayID.isEmpty,
              let source = userInfo["source"]
        else { return nil }
        let timestamp = userInfo["timestamp"].flatMap(Double.init) ?? 0
        self.init(kind: kind, value: value, displayID: displayID,
                  displayName: userInfo["displayName"], source: source, timestamp: timestamp)
        if let parsedVersion = userInfo["version"].flatMap(Int.init) { self.version = parsedVersion }
    }
}
