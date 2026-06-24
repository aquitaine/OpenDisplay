import DisplayDomain
import Foundation

/// A display arrangement the user has marked "protected", so unexpected changes can be detected and
/// (later) restored (Batch-2 #6). Captures the full snapshot plus when it was protected. Persistable
/// alongside the other checkpoints.
public struct ProtectedConfig: Hashable, Sendable, Codable {
    public let snapshot: TopologySnapshot
    public let capturedAt: Date

    public init(snapshot: TopologySnapshot, capturedAt: Date) {
        self.snapshot = snapshot
        self.capturedAt = capturedAt
    }
}

/// Pure drift detection: compares a protected arrangement against the current one, record-by-record,
/// and reports exactly what changed. The decision logic is platform-independent and unit-tested; the
/// host decides what to do with the result (prompt, auto-restore via the existing `ScenePlanner`, …).
public enum DisplayConfigDrifter {
    /// One way the live arrangement diverged from the protected one.
    public enum Change: Hashable, Sendable, Codable {
        case originMoved(DisplayRecordID)
        case modeChanged(DisplayRecordID)
        case rotationChanged(DisplayRecordID)
        case mirrorChanged(DisplayRecordID)
        case activeChanged(DisplayRecordID)
        case mainChanged(from: DisplayRecordID?, to: DisplayRecordID?)
        case disconnected(DisplayRecordID)
        case appeared(DisplayRecordID)
    }

    public struct DriftAnalysis: Hashable, Sendable, Codable {
        public let changes: [Change]
        public var hasDrifted: Bool { !changes.isEmpty }
        public init(changes: [Change]) { self.changes = changes }
    }

    /// Compares two snapshots and returns the ordered, deterministic list of changes.
    public static func detectDrift(protected: TopologySnapshot, current: TopologySnapshot) -> DriftAnalysis {
        let protectedByID = Dictionary(protected.observations.map { ($0.recordID, $0) }, uniquingKeysWith: { a, _ in a })
        let currentByID = Dictionary(current.observations.map { ($0.recordID, $0) }, uniquingKeysWith: { a, _ in a })
        var changes: [Change] = []

        // Per protected display, in a stable order: gone, or a field changed.
        for id in protected.observations.map(\.recordID).sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let p = protectedByID[id] else { continue }
            guard let c = currentByID[id] else { changes.append(.disconnected(id)); continue }
            if p.origin != c.origin { changes.append(.originMoved(id)) }
            if p.mode != c.mode { changes.append(.modeChanged(id)) }
            if p.rotation != c.rotation { changes.append(.rotationChanged(id)) }
            if p.mirrorSourceID != c.mirrorSourceID { changes.append(.mirrorChanged(id)) }
            if p.isActive != c.isActive { changes.append(.activeChanged(id)) }
        }
        // New displays that weren't in the protected arrangement.
        for id in current.observations.map(\.recordID).sorted(by: { $0.rawValue < $1.rawValue })
        where protectedByID[id] == nil {
            changes.append(.appeared(id))
        }
        // The main display moving is an arrangement-level change.
        let protectedMain = protected.observations.first(where: { $0.isMain })?.recordID
        let currentMain = current.observations.first(where: { $0.isMain })?.recordID
        if protectedMain != currentMain {
            changes.append(.mainChanged(from: protectedMain, to: currentMain))
        }
        return DriftAnalysis(changes: changes)
    }
}
