import XCTest
import DisplayDomain
@testable import TopologyCore

final class DisplayRegistryTests: XCTestCase {
    private func fingerprint(vendor: Int? = 1, product: Int? = 1, serial: String? = nil,
                             model: String? = nil) -> DisplayFingerprint {
        DisplayFingerprint(vendorID: vendor, productID: product, serialNumber: serial, modelName: model)
    }

    func testMintsNewRecordForUnknownDisplay() async {
        let registry = await DisplayRegistry(store: InMemoryRegistryStore())
        let record = await registry.resolve(fingerprint: fingerprint(serial: "S1"), cgUUID: "U1")
        let all = await registry.allRecords()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, record.id)
    }

    func testRecognizesSameSerialAsSameRecord() async {
        let registry = await DisplayRegistry(store: InMemoryRegistryStore())
        let first = await registry.resolve(fingerprint: fingerprint(serial: "ABC"), cgUUID: "U1")
        // Same serial, different UUID (e.g. moved to another port) → still the same record.
        let second = await registry.resolve(fingerprint: fingerprint(serial: "ABC"), cgUUID: "U2")
        XCTAssertEqual(first.id, second.id)
        let count = await registry.allRecords().count
        XCTAssertEqual(count, 1)
    }

    func testRecognizesViaCGUUIDWhenNoSerial() async {
        let registry = await DisplayRegistry(store: InMemoryRegistryStore())
        // No serial: a fingerprint-only re-match scores model-family (0.25) < the 0.5 threshold, so
        // recognition here depends on the CG-UUID fast path.
        let first = await registry.resolve(fingerprint: fingerprint(serial: nil), cgUUID: "U1")
        let second = await registry.resolve(fingerprint: fingerprint(serial: nil), cgUUID: "U1")
        XCTAssertEqual(first.id, second.id)
        let count = await registry.allRecords().count
        XCTAssertEqual(count, 1)
    }

    func testMintsDistinctRecordsForDifferentDisplaysWithoutSerial() async {
        let registry = await DisplayRegistry(store: InMemoryRegistryStore())
        _ = await registry.resolve(fingerprint: fingerprint(vendor: 1, product: 1, serial: nil), cgUUID: "U1")
        _ = await registry.resolve(fingerprint: fingerprint(vendor: 2, product: 2, serial: nil), cgUUID: "U2")
        let count = await registry.allRecords().count
        XCTAssertEqual(count, 2)
    }

    func testAliasAndTagPersistAcrossResolve() async {
        let registry = await DisplayRegistry(store: InMemoryRegistryStore())
        let record = await registry.resolve(fingerprint: fingerprint(serial: "S1"), cgUUID: "U1")
        await registry.setAlias("Desk Left", for: record.id)
        await registry.addTag("studio", to: record.id)
        // Re-resolving the same display keeps the user-attached alias/tags.
        let again = await registry.resolve(fingerprint: fingerprint(serial: "S1"), cgUUID: "U1")
        XCTAssertEqual(again.alias, "Desk Left")
        XCTAssertTrue(again.tags.contains("studio"))
    }

    func testStatePersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-registry-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = await DisplayRegistry(store: DiskRegistryStore(directory: directory))
        let record = await first.resolve(fingerprint: fingerprint(serial: "S1", model: "S34J55x"), cgUUID: "U1")
        await first.setAlias("Ultrawide", for: record.id)

        // A fresh registry over the same directory loads the persisted record + alias.
        let second = await DisplayRegistry(store: DiskRegistryStore(directory: directory))
        let reloaded = await second.record(for: record.id)
        XCTAssertEqual(reloaded?.alias, "Ultrawide")
        let resolvedAgain = await second.resolve(fingerprint: fingerprint(serial: "S1"), cgUUID: "U1")
        XCTAssertEqual(resolvedAgain.id, record.id)
    }
}
