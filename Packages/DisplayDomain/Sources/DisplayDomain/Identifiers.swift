import Foundation

/// A stable, app-owned identifier for a physical/logical display, independent of any
/// transient OS display ID. Persistent behavior (aliases, policies, scenes) is keyed on
/// this value, never on a Core Graphics display ID (PRD D-009, REG-003).
public struct DisplayRecordID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Mints a fresh, sortable record ID (`disp_<ulid-like>`).
    public static func generate(now: Date = Date()) -> DisplayRecordID {
        let stamp = UInt64(max(0, now.timeIntervalSince1970 * 1000)).description
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        return DisplayRecordID(rawValue: "disp_\(stamp)_\(suffix)")
    }

    /// The id observers mint for a display whose persistent Core Graphics UUID is available. Group
    /// membership, the settings ledgers, and the audit log all carry this form, so anything that has
    /// to look such a display up in the registry (which indexes by the bare UUID) goes through here
    /// and `cgUUID` rather than re-spelling the prefix. ::
    ///
    ///     DisplayRecordID.forCGUUID("U1").cgUUID
    ///     ok: "U1"
    public static func forCGUUID(_ uuid: String) -> DisplayRecordID {
        DisplayRecordID(rawValue: "\(cgUUIDPrefix)\(uuid)")
    }

    /// The Core Graphics UUID inside a `cg:<uuid>` id, or nil for any other id form — a UUID-less
    /// `cgid:<n>` observation, or a registry-minted `disp_…` record id.
    public var cgUUID: String? {
        guard rawValue.hasPrefix(Self.cgUUIDPrefix) else { return nil }
        return String(rawValue.dropFirst(Self.cgUUIDPrefix.count))
    }

    private static let cgUUIDPrefix = "cg:"

    public var description: String { rawValue }
}

/// Identifies a single serialized topology/lifecycle transaction. Every mutation carries
/// one of these for correlation across the coordinator, providers, logs, and the result
/// envelope (PRD §10.4).
public struct TransactionID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> TransactionID {
        TransactionID(rawValue: "txn_\(UUID().uuidString)")
    }

    public var description: String { rawValue }
}

/// Identifies a last-known-safe checkpoint (PRD §9.4, DIA-008).
public struct CheckpointID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> CheckpointID {
        CheckpointID(rawValue: "cp_\(UUID().uuidString)")
    }

    public var description: String { rawValue }
}

/// A monotonically increasing version of the normalized set of observed displays. Bumped
/// only after the registry has stabilized following OS events, so capability snapshots and
/// transactions can be invalidated when the world changes underneath them (PRD §10.4).
public struct TopologyGeneration: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    public static let initial = TopologyGeneration(0)

    public func next() -> TopologyGeneration {
        TopologyGeneration(value &+ 1)
    }

    public static func < (lhs: TopologyGeneration, rhs: TopologyGeneration) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String { "gen:\(value)" }
}

/// The actor that requested a change, recorded on every transaction and audit entry (AUT-010).
public enum Actor: String, Hashable, Sendable, Codable {
    case ui
    case cli
    case appIntent
    case rule
    case httpAPI
    case recovery
    case system
    /// An `opendisplay://` URL-scheme invocation (a distinct automation front door, like `cli`).
    case url
    /// The wake-convergence engine keeping a promise across a sleep: re-asserting a ledger "off"
    /// macOS undid, or the always-one-active net lighting its fallback. Distinct from `system` so
    /// "why did my display just switch?" is answerable to the exact path from the audit trail.
    case wakeConvergence
}
