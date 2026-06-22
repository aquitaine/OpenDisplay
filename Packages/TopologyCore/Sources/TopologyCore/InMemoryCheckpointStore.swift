import DisplayDomain
import Foundation

/// A simple in-memory `CheckpointStoring` implementation. Useful for SwiftUI previews, the
/// composition root before a disk-backed store exists, and tests. The production store is
/// atomic and rescue-readable on disk (PRD §10.8) and lands in M0.
public actor InMemoryCheckpointStore: CheckpointStoring {
    private var byID: [CheckpointID: Checkpoint] = [:]
    private var latestID: CheckpointID?

    public init() {}

    public func writeAtomic(_ checkpoint: Checkpoint) async throws {
        byID[checkpoint.id] = checkpoint
        latestID = checkpoint.id
    }

    public func restore(_ id: CheckpointID) async throws -> Checkpoint? {
        byID[id]
    }

    public func latest() async -> Checkpoint? {
        latestID.flatMap { byID[$0] }
    }
}
