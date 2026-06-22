import DisplayDomain
import Foundation

/// Persisted registry state: the remembered display records plus a same-Mac fast-path index from
/// the (stable on this machine) CG display UUID to a record. The UUID index is a routing hint, not
/// portable identity — cross-machine recognition relies on the scored fingerprint.
public struct RegistryState: Hashable, Sendable, Codable {
    public var records: [DisplayRecord]
    public var cgUUIDIndex: [String: DisplayRecordID]

    public init(records: [DisplayRecord] = [], cgUUIDIndex: [String: DisplayRecordID] = [:]) {
        self.records = records
        self.cgUUIDIndex = cgUUIDIndex
    }
}

/// Persistence backend for the registry.
public protocol RegistryStoring: Sendable {
    func load() async -> RegistryState
    func save(_ state: RegistryState) async
}

/// In-memory store for tests and previews.
public actor InMemoryRegistryStore: RegistryStoring {
    private var state: RegistryState
    public init(_ state: RegistryState = RegistryState()) { self.state = state }
    public func load() -> RegistryState { state }
    public func save(_ state: RegistryState) { self.state = state }
}

/// Atomic JSON store at `<dir>/registry.json` (pure Foundation; covered by `make test`).
public struct DiskRegistryStore: RegistryStoring {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("registry.json")
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

    public func load() async -> RegistryState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(RegistryState.self, from: data) else {
            return RegistryState()
        }
        return state
    }

    public func save(_ state: RegistryState) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}

/// The source of remembered display identity (PRD §10.5, REG-003/004/005). Resolves a live
/// observation's fingerprint to a stable `DisplayRecord` — recognizing a display we've seen before
/// or minting a new record — and owns user-attached alias/tag/pairing edits. Resolution order:
///   1. exact EDID serial match (definitive),
///   2. same-Mac CG-UUID fast path,
///   3. best scored fingerprint match above the recognition threshold (`IdentityScorer`),
///   4. otherwise mint a new record.
/// Two identical monitors with no serial therefore stay distinct until paired, rather than being
/// silently merged.
public actor DisplayRegistry {
    private var state: RegistryState
    private let store: any RegistryStoring
    private let recognitionThreshold: Double

    public init(store: any RegistryStoring, recognitionThreshold: Double = 0.5) async {
        self.store = store
        self.recognitionThreshold = recognitionThreshold
        self.state = await store.load()
    }

    public func allRecords() -> [DisplayRecord] { state.records }

    public func record(for id: DisplayRecordID) -> DisplayRecord? {
        state.records.first { $0.id == id }
    }

    /// Resolves a fingerprint (+ optional CG UUID) to a stable record, recognizing or minting.
    public func resolve(
        fingerprint: DisplayFingerprint,
        cgUUID: String?,
        displayClass: DisplayClass = .unknown,
        now: Date = Date()
    ) async -> DisplayRecord {
        // 1. Exact serial match.
        if let serial = fingerprint.serialNumber ?? fingerprint.serialHash,
           let match = state.records.first(where: {
               ($0.fingerprint.serialNumber ?? $0.fingerprint.serialHash) == serial
           }) {
            return await touch(match.id, fingerprint: fingerprint, cgUUID: cgUUID, now: now)
        }

        // 2. Same-Mac CG-UUID fast path.
        if let cgUUID, let id = state.cgUUIDIndex[cgUUID], record(for: id) != nil {
            return await touch(id, fingerprint: fingerprint, cgUUID: cgUUID, now: now)
        }

        // 3. Best scored fingerprint match.
        let best = state.records
            .map { ($0, IdentityScorer.score(observed: fingerprint, candidate: $0).score) }
            .max { $0.1 < $1.1 }
        if let best, best.1 >= recognitionThreshold {
            return await touch(best.0.id, fingerprint: fingerprint, cgUUID: cgUUID, now: now)
        }

        // 4. Mint a new record.
        let record = DisplayRecord(
            id: .generate(now: now), fingerprint: fingerprint, displayClass: displayClass, lastSeen: now
        )
        state.records.append(record)
        if let cgUUID { state.cgUUIDIndex[cgUUID] = record.id }
        await persist()
        return record
    }

    public func setAlias(_ alias: String?, for id: DisplayRecordID) async {
        try? await mutate(id) { $0.alias = alias?.isEmpty == true ? nil : alias }
    }

    public func addTag(_ tag: String, to id: DisplayRecordID) async {
        try? await mutate(id) { $0.tags.insert(tag) }
    }

    public func removeTag(_ tag: String, from id: DisplayRecordID) async {
        try? await mutate(id) { $0.tags.remove(tag) }
    }

    /// Marks a record as an explicit user pairing, lifting its identity confidence (REG-004).
    public func confirmPairing(for id: DisplayRecordID) async {
        try? await mutate(id) { $0.pairingConfirmed = true }
    }

    // MARK: - Private

    private enum RegistryError: Error { case unknownRecord }

    private func mutate(_ id: DisplayRecordID, _ change: (inout DisplayRecord) -> Void) async throws {
        guard let index = state.records.firstIndex(where: { $0.id == id }) else {
            throw RegistryError.unknownRecord
        }
        change(&state.records[index])
        await persist()
    }

    private func touch(
        _ id: DisplayRecordID, fingerprint: DisplayFingerprint, cgUUID: String?, now: Date
    ) async -> DisplayRecord {
        let index = state.records.firstIndex { $0.id == id }!
        state.records[index].fingerprint = Self.merged(state.records[index].fingerprint, fingerprint)
        state.records[index].lastSeen = now
        if let cgUUID { state.cgUUIDIndex[cgUUID] = id }
        await persist()
        return state.records[index]
    }

    private func persist() async {
        await store.save(state)
    }

    /// Fills gaps in `base` from `new` without dropping evidence we already had.
    private static func merged(_ base: DisplayFingerprint, _ new: DisplayFingerprint) -> DisplayFingerprint {
        DisplayFingerprint(
            vendorID: new.vendorID ?? base.vendorID,
            productID: new.productID ?? base.productID,
            serialNumber: new.serialNumber ?? base.serialNumber,
            serialHash: new.serialHash ?? base.serialHash,
            modelName: new.modelName ?? base.modelName,
            manufactureYear: new.manufactureYear ?? base.manufactureYear,
            manufactureWeek: new.manufactureWeek ?? base.manufactureWeek,
            physicalWidthMM: new.physicalWidthMM ?? base.physicalWidthMM,
            physicalHeightMM: new.physicalHeightMM ?? base.physicalHeightMM,
            edidHash: new.edidHash ?? base.edidHash
        )
    }
}
