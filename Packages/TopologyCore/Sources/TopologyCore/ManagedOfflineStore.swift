import DisplayDomain
import Foundation

/// A display OpenDisplay logically turned off, remembered so it stays visible and re-enableable —
/// in the menu, from the CLI, and after a relaunch.
///
/// A logically-disabled display drops out of `CGGetOnlineDisplayList` entirely, so it cannot be
/// rediscovered by enumeration: this record IS the only handle to it. `cgID` matters as much as
/// `recordID` — reconnect resolves by raw display id (`cgid:<n>`), because the UUID path needs the
/// display to be online, which is exactly what it isn't.
public struct ManagedOfflineDisplay: Hashable, Sendable, Codable, Identifiable {
    public var recordID: DisplayRecordID
    public var cgID: UInt32
    public var name: String
    public var displayClass: DisplayClass
    /// When macOS relit this display during a wake, while its "off" was still owed. Nil in the
    /// normal state (the display really is off). The stamp is what lets the owed "off" outlive the
    /// wake window: the window exists to tell the user's own re-enable apart from macOS's, but the
    /// covering display's return can outlast it (time-to-unlock is unbounded), and a stamped entry
    /// decays on *convergence* — the re-assert putting the display back off — not on a clock.
    /// Optional and absent from old ledgers, so the app and CLI read either format.
    public var relitDuringWakeAt: Date?

    public var id: DisplayRecordID { recordID }

    public init(recordID: DisplayRecordID, cgID: UInt32, name: String, displayClass: DisplayClass,
                relitDuringWakeAt: Date? = nil) {
        self.recordID = recordID
        self.cgID = cgID
        self.name = name
        self.displayClass = displayClass
        self.relitDuringWakeAt = relitDuringWakeAt
    }

    /// The selector reconnect should use: the raw display id when we have one, since a disabled
    /// display is absent from the online list and can't be resolved through its CG UUID.
    public var reconnectID: DisplayRecordID {
        cgID != 0 ? DisplayRecordID(rawValue: "cgid:\(cgID)") : recordID
    }
}

/// Atomic, on-disk store for the managed-offline list, shared by the app and the CLI.
///
/// Shared deliberately: the app is what turns a display off, but the CLI is what you reach for
/// when the display you turned off was the one you needed — so both must read the same file
/// through the same type. Two definitions of this format would drift, and the failure mode is a
/// display nothing can recover. Pure Foundation, so `make test` covers it.
public struct ManagedOfflineStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("managed-offline.json")
    }

    /// The shared Application Support location (the same folder settings + checkpoints use).
    public static func defaultDirectory(
        appName: String = "OpenDisplay",
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    /// The remembered off-displays, or an empty list when the file is absent or unreadable — a
    /// corrupt file must never stop the app launching, and an empty list is the safe reading
    /// (nothing is owed a reconnect).
    public func load() -> [ManagedOfflineDisplay] {
        guard let data = try? Data(contentsOf: fileURL),
              let displays = try? JSONDecoder().decode([ManagedOfflineDisplay].self, from: data)
        else { return [] }
        return displays
    }

    public func save(_ displays: [ManagedOfflineDisplay]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(displays).write(to: fileURL, options: .atomic)
    }
}
