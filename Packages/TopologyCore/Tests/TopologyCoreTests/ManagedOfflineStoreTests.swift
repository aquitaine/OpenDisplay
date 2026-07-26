import DisplayDomain
import XCTest
@testable import TopologyCore

final class ManagedOfflineStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManagedOfflineStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func display(_ raw: String, cgID: UInt32 = 1) -> ManagedOfflineDisplay {
        ManagedOfflineDisplay(recordID: DisplayRecordID(rawValue: raw), cgID: cgID,
                              name: "Built-in Retina Display", displayClass: .builtIn)
    }

    func testLoadReturnsEmptyWhenAbsent() {
        XCTAssertTrue(ManagedOfflineStore(directory: directory).load().isEmpty)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ManagedOfflineStore(directory: directory)
        let displays = [display("cg:ABC", cgID: 1), display("cg:DEF", cgID: 7)]
        try store.save(displays)
        XCTAssertEqual(store.load(), displays)
    }

    func testCorruptFileLoadsAsEmptyRatherThanThrowing() throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("managed-offline.json"))
        XCTAssertTrue(ManagedOfflineStore(directory: directory).load().isEmpty)
    }

    /// The app wrote this exact shape before the store existed; a user upgrading must not lose the
    /// record of a display that is currently turned off — it is the only handle back to it.
    func testDecodesTheFormatTheAppWroteBeforeThisStoreExisted() throws {
        let legacy = """
        [{"recordID":{"rawValue":"cg:37D8832A-2D66-02CA-B9F7-8F30A301B230"},"cgID":1,\
        "displayClass":"builtIn","name":"Built-in Retina Display"}]
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("managed-offline.json"))
        let loaded = ManagedOfflineStore(directory: directory).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.cgID, 1)
        XCTAssertEqual(loaded.first?.displayClass, .builtIn)
        XCTAssertEqual(loaded.first?.recordID.rawValue, "cg:37D8832A-2D66-02CA-B9F7-8F30A301B230")
    }

    func testReconnectIDPrefersTheRawDisplayID() {
        // A disabled display is absent from the online list, so UUID resolution fails — reconnect
        // must go through `cgid:<n>`.
        XCTAssertEqual(display("cg:ABC", cgID: 3).reconnectID.rawValue, "cgid:3")
    }

    func testReconnectIDFallsBackToTheRecordIDWithoutACGID() {
        XCTAssertEqual(display("cg:ABC", cgID: 0).reconnectID.rawValue, "cg:ABC")
    }
}
