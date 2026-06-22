import DisplayDomain
import Foundation

/// Atomic, rescue-readable, on-disk `CheckpointStoring` (PRD §10.8, §9.4, DIA-008).
///
/// Each checkpoint is written as a self-contained JSON file under `<directory>/checkpoints/`, and
/// the most recent one is also mirrored to `<directory>/latest.json` so the independent rescue
/// process can find the last-known-safe state by reading a single well-known file — no scanning,
/// no shared in-process state, no secrets. Writes go through `Data.write(options: .atomic)` (temp
/// file + rename) so a crash mid-write can never leave a torn checkpoint.
///
/// Pure Foundation, so it lives in the cross-platform core and is exercised by `make test`; the
/// macOS app and the rescue utility both point it at the same Application Support directory.
public struct DiskCheckpointStore: CheckpointStoring {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The shared Application Support location both the app and the rescue utility use. Creating
    /// the store does no I/O; this resolves (and creates) the base directory.
    public static func defaultDirectory(
        appName: String = "OpenDisplay",
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public func writeAtomic(_ checkpoint: Checkpoint) async throws {
        let checkpointsDir = directory.appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(checkpoint)
        try data.write(to: fileURL(for: checkpoint.id, in: checkpointsDir), options: .atomic)
        // Mirror to the well-known pointer the rescue process reads first.
        try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
    }

    public func restore(_ id: CheckpointID) async throws -> Checkpoint? {
        let checkpointsDir = directory.appendingPathComponent("checkpoints", isDirectory: true)
        let url = fileURL(for: id, in: checkpointsDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try Self.decoder().decode(Checkpoint.self, from: data)
    }

    public func latest() async -> Checkpoint? {
        let url = directory.appendingPathComponent("latest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder().decode(Checkpoint.self, from: data)
    }

    // MARK: - Private

    private func fileURL(for id: CheckpointID, in checkpointsDir: URL) -> URL {
        checkpointsDir.appendingPathComponent("\(id.rawValue).json")
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Stable, human-inspectable output for the rescue utility and diffs.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
