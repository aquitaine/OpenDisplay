import Foundation

/// Copies macOS's saved display configuration aside before OpenDisplay turns a display off.
///
/// Turning a display off is committed app-only and is meant to leave nothing behind, but the window
/// server still rewrites its saved display sets when the arrangement changes (observed: a set for
/// "the remaining displays" appears in `com.apple.windowserver.displays.plist` within moments).
/// Issue #40 is a display stranded by one of those saved entries, and the report could only be
/// reconstructed by hand after the fact. A copy taken just before each disconnect makes the next
/// one a diff — and gives the user their old arrangement back if they have to reset the files.
///
/// Read-only towards the system: this never writes, moves, or deletes the originals. Pure
/// Foundation, shared by the app and the CLI. ::
///
///     snapshot(label: "Desk", now: 2026-10-05T12:00:00Z)
///     ok: …/display-config-backups/20261005T120000Z-Desk/ holding a copy of each readable plist
///
///     a sixth snapshot
///     ok: the oldest folder is removed — `keep` newest remain
public enum WindowServerConfigBackup {
    public static let keep = 5

    /// The system-wide file plus this user's per-host files.
    public static func defaultSources(fileManager: FileManager = .default) -> [URL] {
        let system = URL(fileURLWithPath: "/Library/Preferences/com.apple.windowserver.displays.plist")
        let byHost = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/ByHost", isDirectory: true)
        let perHost = ((try? fileManager.contentsOfDirectory(
            at: byHost, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("com.apple.windowserver.displays")
                && $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return [system] + perHost
    }

    public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        try ManagedOfflineStore.defaultDirectory(fileManager: fileManager)
            .appendingPathComponent("display-config-backups", isDirectory: true)
    }

    /// Copies every readable source into a new timestamped folder under `root`, prunes to the
    /// `keep` newest, and returns the folder — or nil when nothing could be copied. Best-effort by
    /// design: a failed backup must never be the reason a disconnect doesn't happen.
    @discardableResult
    public static func snapshot(sources: [URL], into root: URL, label: String, now: Date,
                                keep: Int = keep, fileManager: FileManager = .default) -> URL? {
        let folder = root.appendingPathComponent(folderName(label: label, now: now), isDirectory: true)
        guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return nil }
        var copied = 0
        for source in sources {
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            if (try? fileManager.copyItem(at: source, to: destination)) != nil { copied += 1 }
        }
        guard copied > 0 else {
            try? fileManager.removeItem(at: folder)
            return nil
        }
        prune(root, keep: keep, fileManager: fileManager)
        return folder
    }

    /// Timestamp first so folder names sort oldest → newest; the label is only there for a human.
    static func folderName(label: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let safe = String(label.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(40))
        return safe.isEmpty ? formatter.string(from: now) : "\(formatter.string(from: now))-\(safe)"
    }

    static func prune(_ root: URL, keep: Int, fileManager: FileManager) {
        let folders = ((try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for stale in folders.dropLast(max(0, keep)) { try? fileManager.removeItem(at: stale) }
    }
}
