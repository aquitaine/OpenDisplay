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
}
