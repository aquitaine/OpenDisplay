import XCTest
import DisplayDomain
@testable import TopologyCore

final class AuditLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-audit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ id: String, status: String = "committed") -> AuditEntry {
        AuditEntry(timestamp: Date(timeIntervalSinceReferenceDate: 1000), actor: .cli,
                   command: "disconnect", transactionId: id, status: status, targets: ["ext"])
    }

    func testAppendThenRecentPreservesOrder() async {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("txn_1"))
        await log.append(entry("txn_2"))
        let recent = await log.recent(limit: 10)
        XCTAssertEqual(recent.map(\.transactionId), ["txn_1", "txn_2"])
    }

    func testRecentRespectsLimit() async {
        let log = DiskAuditLog(directory: directory)
        for i in 1...5 { await log.append(entry("txn_\(i)")) }
        let recent = await log.recent(limit: 2)
        XCTAssertEqual(recent.map(\.transactionId), ["txn_4", "txn_5"])
    }

    func testEmptyWhenAbsent() async {
        let recent = await DiskAuditLog(directory: directory).recent(limit: 10)
        XCTAssertTrue(recent.isEmpty)
    }

    func testTornFinalLineIsSkipped() async throws {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("txn_good"))
        // Simulate a crash mid-append leaving a partial trailing line.
        let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("audit.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"partial\":".utf8))
        try handle.close()
        let recent = await log.recent(limit: 10)
        XCTAssertEqual(recent.map(\.transactionId), ["txn_good"])
    }

    func testWritesOneJSONObjectPerLine() async throws {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("a"))
        await log.append(entry("b"))
        let text = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 2)
    }

    /// A wake-convergence entry survives the disk round-trip next to entries from other actors —
    /// the new actor is just another raw value in the same JSONL shape.
    func testWakeConvergenceEntryRoundTripsAlongsideOtherActors() async throws {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("txn_cli"))
        await log.append(AuditEntry(
            timestamp: Date(timeIntervalSinceReferenceDate: 2000), actor: .wakeConvergence,
            command: "reassertOff", transactionId: "txn_reassertOff", status: "committed",
            targets: ["builtin"]))
        let recent = await log.recent(limit: 10)
        XCTAssertEqual(recent.map(\.actor), [.cli, .wakeConvergence])
        XCTAssertEqual(recent.last?.command, "reassertOff")
        let text = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("\"actor\":\"wakeConvergence\""))
    }
    func testRecentSkipsInvalidUTF8BeforeValidTail() async throws {
        let url = directory.appendingPathComponent("audit.jsonl")
        try Data([0xFF, 0xFE, 0x0A]).write(to: url)
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("newest"))
        let rows = await log.recent(limit: 1)
        XCTAssertEqual(rows.map(\.transactionId), ["newest"])
    }

    func testRecentHandlesEntriesSpanningReadBlocksAndTornTail() async throws {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("older"))
        let longID = String(repeating: "x", count: 20_000)
        await log.append(entry(longID))
        await log.append(entry("newest"))
        let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("audit.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{unfinished".utf8))
        try handle.close()
        let rows = await log.recent(limit: 2)
        XCTAssertEqual(rows.map(\.transactionId), [longID, "newest"])
    }

    func testNonpositiveLimitReturnsNoEntries() async {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("saved"))
        let zero = await log.recent(limit: 0)
        let negative = await log.recent(limit: -1)
        XCTAssertTrue(zero.isEmpty)
        XCTAssertTrue(negative.isEmpty)
    }

    func testCompleteFinalEntryWithoutNewlineIsIncluded() async throws {
        let log = DiskAuditLog(directory: directory)
        await log.append(entry("older"))
        await log.append(entry("newest"))
        let url = directory.appendingPathComponent("audit.jsonl")
        var bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.removeLast(), 0x0A)
        try bytes.write(to: url)
        let rows = await log.recent(limit: 1)
        XCTAssertEqual(rows.map(\.transactionId), ["newest"])
    }
}
