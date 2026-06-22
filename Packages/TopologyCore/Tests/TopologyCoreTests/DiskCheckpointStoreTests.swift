import XCTest
import DisplayDomain
@testable import TopologyCore

final class DiskCheckpointStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-checkpoint-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // Fixed timestamp so encode/decode round-trips to an exactly equal value.
    private let when = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func makeCheckpoint(suffix: String, generation: UInt64) -> Checkpoint {
        let gen = TopologyGeneration(generation)
        let observations = [
            DisplayObservation(recordID: .init(rawValue: "cg:AAAA"), cgDisplayID: 1, isActive: true,
                               isMain: true, displayClass: .builtIn, generation: gen, observedAt: when),
            DisplayObservation(recordID: .init(rawValue: "cg:BBBB"), cgDisplayID: 2, isActive: false,
                               displayClass: .external, generation: gen, observedAt: when)
        ]
        let offline = [
            ManagedOfflineRecord(displayID: .init(rawValue: "cg:BBBB"), actor: .ui, reason: "test",
                                 disconnectedAt: when, providerID: "test.provider")
        ]
        return Checkpoint(
            id: CheckpointID(rawValue: "cp_\(suffix)"),
            transactionID: TransactionID(rawValue: "txn_\(suffix)"),
            generation: gen,
            observations: observations,
            mainDisplayID: .init(rawValue: "cg:AAAA"),
            managedOffline: offline,
            createdAt: when
        )
    }

    func testWriteThenLatestRoundTrips() async throws {
        let store = DiskCheckpointStore(directory: directory)
        let checkpoint = makeCheckpoint(suffix: "one", generation: 3)
        try await store.writeAtomic(checkpoint)
        let latest = await store.latest()
        XCTAssertEqual(latest, checkpoint)
    }

    func testRestoreByID() async throws {
        let store = DiskCheckpointStore(directory: directory)
        let checkpoint = makeCheckpoint(suffix: "two", generation: 5)
        try await store.writeAtomic(checkpoint)
        let restored = try await store.restore(checkpoint.id)
        XCTAssertEqual(restored, checkpoint)
    }

    func testLatestReflectsMostRecentWrite() async throws {
        let store = DiskCheckpointStore(directory: directory)
        let first = makeCheckpoint(suffix: "first", generation: 1)
        let second = makeCheckpoint(suffix: "second", generation: 2)
        try await store.writeAtomic(first)
        try await store.writeAtomic(second)
        let latest = await store.latest()
        XCTAssertEqual(latest, second)
        // The earlier checkpoint is still individually restorable by id.
        let restoredFirst = try await store.restore(first.id)
        XCTAssertEqual(restoredFirst, first)
    }

    func testLatestIsNilOnEmptyDirectory() async {
        let store = DiskCheckpointStore(directory: directory)
        let latest = await store.latest()
        XCTAssertNil(latest)
    }

    func testRestoreUnknownIDIsNil() async throws {
        let store = DiskCheckpointStore(directory: directory)
        let restored = try await store.restore(CheckpointID(rawValue: "cp_missing"))
        XCTAssertNil(restored)
    }

    /// The rescue contract: the latest checkpoint must be readable by an independent reader from a
    /// well-known file, with no store instance and no shared state — just JSON + Codable.
    func testLatestFileIsIndependentlyReadable() async throws {
        let store = DiskCheckpointStore(directory: directory)
        let checkpoint = makeCheckpoint(suffix: "rescue", generation: 7)
        try await store.writeAtomic(checkpoint)

        let latestURL = directory.appendingPathComponent("latest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: latestURL.path))

        let data = try Data(contentsOf: latestURL)
        let decoded = try JSONDecoder().decode(Checkpoint.self, from: data)
        XCTAssertEqual(decoded, checkpoint)
    }
}
