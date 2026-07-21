import DisplayDomain
import Foundation

/// One recorded lifecycle command for the activity/audit trail (AUT-010): who did what, when, to
/// which displays, and how it ended. Stable + Codable so the rescue utility and diagnostics can
/// read history.
public struct AuditEntry: Hashable, Sendable, Codable {
    public var timestamp: Date
    public var actor: Actor
    public var command: String
    public var transactionId: String
    public var status: String
    public var targets: [String]

    public init(
        timestamp: Date, actor: Actor, command: String,
        transactionId: String, status: String, targets: [String]
    ) {
        self.timestamp = timestamp
        self.actor = actor
        self.command = command
        self.transactionId = transactionId
        self.status = status
        self.targets = targets
    }
}

/// Append-only activity trail. The coordinator/gateway records every command here.
public protocol AuditLogging: Sendable {
    func append(_ entry: AuditEntry) async
    func recent(limit: Int) async -> [AuditEntry]
}

/// In-memory audit trail for tests and previews.
public actor InMemoryAuditLog: AuditLogging {
    private var entries: [AuditEntry] = []
    public init() {}
    public func append(_ entry: AuditEntry) { entries.append(entry) }
    public func recent(limit: Int) -> [AuditEntry] { Array(entries.suffix(limit)) }
    public var all: [AuditEntry] { entries }
}

/// Append-only, rescue-readable audit log: one JSON object per line (JSONL) in Application Support.
/// A torn final line from a crash is skipped on read, never breaking the rest of the history.
/// Pure Foundation, so it lives in the cross-platform core and is exercised by `make test`.
public struct DiskAuditLog: AuditLogging {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("audit.jsonl")
    }

    public static func defaultDirectory(
        appName: String = "OpenDisplay",
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public func append(_ entry: AuditEntry) async {
        guard let encoded = try? Self.encoder().encode(entry) else { return }
        var line = encoded
        line.append(0x0A) // newline
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // O_APPEND: the app, CLI, and out-of-process App Intents all append to this file, and a
        // kernel-atomic append per write() is what keeps concurrent entries from interleaving
        // mid-line (seek-then-write is two steps, so two writers could land inside each other's
        // lines — recent() then drops both as torn). A single small write stays one syscall.
        let fd = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try? handle.write(contentsOf: line)
        try? handle.close()
    }

    public func recent(limit: Int) async -> [AuditEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = Self.decoder()
        let entries = text.split(separator: "\n").compactMap { line in
            try? decoder.decode(AuditEntry.self, from: Data(line.utf8))
        }
        return Array(entries.suffix(limit))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // single line per entry — no pretty printing
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
