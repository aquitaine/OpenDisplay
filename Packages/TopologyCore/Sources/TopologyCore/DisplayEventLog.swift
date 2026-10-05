import Foundation

/// A rolling, on-disk timeline of what macOS reported about the displays, written every time the
/// topology moves or OpenDisplay acts on it.
///
/// The audit log records what the app *did*; this records what the system *said* before and after —
/// which displays were online, active, asleep, and in what mode. A display that fails to come back
/// (issue #40) is only explicable from that sequence, and until now it existed nowhere: by the time
/// a user reports a black monitor, the moment that mattered is gone. Local only; it leaves the Mac
/// only inside a diagnostics bundle the user exports and attaches themselves. ::
///
///     {"at":"…","reason":"disconnect:committed","online":2,"active":1,"owed":["Desk"],
///      "displays":[{"id":3,"vendor":7789,"online":true,"active":false,…}, …]}
public enum DisplayEventLog {
    /// One display as Core Graphics reports it at an instant.
    public struct Row: Hashable, Sendable, Codable {
        public var id: UInt32
        public var uuid: String?
        public var vendor: UInt32
        public var model: UInt32
        public var builtIn: Bool
        public var online: Bool
        public var active: Bool
        public var asleep: Bool
        public var main: Bool
        public var mirrorOf: UInt32?
        public var width: Int
        public var height: Int
        public var refreshHz: Double
        public var modeCount: Int

        public init(id: UInt32, uuid: String?, vendor: UInt32, model: UInt32, builtIn: Bool,
                    online: Bool, active: Bool, asleep: Bool, main: Bool, mirrorOf: UInt32?,
                    width: Int, height: Int, refreshHz: Double, modeCount: Int) {
            self.id = id
            self.uuid = uuid
            self.vendor = vendor
            self.model = model
            self.builtIn = builtIn
            self.online = online
            self.active = active
            self.asleep = asleep
            self.main = main
            self.mirrorOf = mirrorOf
            self.width = width
            self.height = height
            self.refreshHz = refreshHz
            self.modeCount = modeCount
        }
    }

    public struct Entry: Hashable, Sendable, Codable {
        public var at: Date
        /// What prompted the entry: `launch`, `topology`, `sleep`, `wake`, `disconnect:<status>`,
        /// `reconnect:<status>`, `export`.
        public var reason: String
        public var online: Int
        public var active: Int
        /// Names of displays the app is holding off (the managed-offline ledger) at this instant.
        public var owed: [String]
        public var displays: [Row]

        public init(at: Date, reason: String, owed: [String], displays: [Row]) {
            self.at = at
            self.reason = reason
            self.online = displays.filter(\.online).count
            self.active = displays.filter(\.active).count
            self.owed = owed
            self.displays = displays
        }
    }

    public static let fileName = "display-events.jsonl"
    /// Past this size the file is cut back to its newest `keepLines` lines. A topology change is a
    /// few hundred bytes, so this is weeks of history for a few hundred kilobytes.
    public static let rotateAtBytes = 512 * 1024
    public static let keepLines = 800

    public static func line(for entry: Entry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The newest `keepLines` lines of an over-long log, or nil when no trim is needed.
    public static func trimmed(_ contents: String, rotateAtBytes: Int = rotateAtBytes,
                               keepLines: Int = keepLines) -> String? {
        guard contents.utf8.count > rotateAtBytes else { return nil }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(keepLines).joined(separator: "\n") + "\n"
    }
}

/// Appends `DisplayEventLog` entries to `display-events.jsonl`. An actor so the app's main actor
/// never waits on the disk and concurrent appends can't interleave within this process; the CLI's
/// occasional append from another process uses O_APPEND like the audit log.
public actor DiskDisplayEventLog {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(DisplayEventLog.fileName)
    }

    public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        try ManagedOfflineStore.defaultDirectory(fileManager: fileManager)
    }

    public func append(_ entry: DisplayEventLog.Entry) {
        guard let line = DisplayEventLog.line(for: entry),
              let data = (line + "\n").data(using: .utf8) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { return }
        data.withUnsafeBytes { _ = write(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
        rotateIfNeeded()
    }

    private func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > DisplayEventLog.rotateAtBytes,
              let contents = try? String(contentsOf: fileURL, encoding: .utf8),
              let trimmed = DisplayEventLog.trimmed(contents) else { return }
        try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
