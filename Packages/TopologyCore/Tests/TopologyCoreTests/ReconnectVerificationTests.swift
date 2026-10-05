import DisplayDomain
import XCTest
@testable import TopologyCore

final class ReconnectVerificationTests: XCTestCase {
    private typealias Verification = ReconnectVerification

    private let desk = ManagedOfflineDisplay(
        recordID: DisplayRecordID(rawValue: "cg:DESK"), cgID: 7, name: "Desk", displayClass: .external)

    func testALitDisplayIsConfirmedHoweverLongItTook() {
        XCTAssertEqual(Verification.next(isLit: true, waited: 0, escalated: false), .confirmed)
        XCTAssertEqual(Verification.next(isLit: true, waited: 60, escalated: true), .confirmed)
    }

    func testAMissingDisplayIsGivenTimeToTrainItsLink() {
        XCTAssertEqual(Verification.next(isLit: false, waited: 2, escalated: false),
                       .lookAgain(after: Verification.pollStep))
    }

    func testTheStrongerRestoreIsTriedOnceAfterTheFirstWait() {
        XCTAssertEqual(Verification.next(isLit: false, waited: Verification.settleTimeout,
                                         escalated: false), .escalate)
    }

    func testTheEscalationGetsItsOwnWaitBeforeGivingUp() {
        XCTAssertEqual(Verification.next(isLit: false, waited: 1, escalated: true),
                       .lookAgain(after: Verification.pollStep))
        XCTAssertEqual(Verification.next(isLit: false, waited: Verification.settleTimeout,
                                         escalated: true), .failed)
    }

    func testFailureIsAuditedAgainstTheDisplayAndNeverAsCommitted() {
        let entry = Verification.failureAudit(of: desk, actor: .ui, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entry.command, "reconnectUnverified")
        XCTAssertEqual(entry.status, "failed")
        XCTAssertEqual(entry.targets, ["cg:DESK"])
    }

    func testAnOldLedgerWithoutTheFailureStampStillDecodes() throws {
        let legacy = Data(#"[{"recordID":{"rawValue":"cg:DESK"},"cgID":7,"name":"Desk","displayClass":"external"}]"#.utf8)
        let decoded = try JSONDecoder().decode([ManagedOfflineDisplay].self, from: legacy)
        XCTAssertEqual(decoded, [desk])
        XCTAssertNil(decoded[0].reconnectFailedAt)
    }
}

final class WindowServerConfigBackupTests: XCTestCase {
    private var root: URL!
    private var sourceDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-backup-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("backups", isDirectory: true)
        sourceDir = base.appendingPathComponent("prefs", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func source(_ name: String, _ contents: String = "x") throws -> URL {
        let url = sourceDir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

    func testSnapshotCopiesEachReadableSourceAndLeavesTheOriginalAlone() throws {
        let system = try source("com.apple.windowserver.displays.plist", "system")
        let missing = sourceDir.appendingPathComponent("gone.plist")
        let folder = try XCTUnwrap(WindowServerConfigBackup.snapshot(
            sources: [system, missing], into: root, label: "Desk 34\"", now: at(0)))
        let copy = folder.appendingPathComponent("com.apple.windowserver.displays.plist")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "system")
        XCTAssertEqual(try String(contentsOf: system, encoding: .utf8), "system")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("gone.plist").path))
        XCTAssertTrue(folder.lastPathComponent.hasSuffix("-Desk-34-"))
    }

    func testNothingReadableLeavesNoEmptyFolderBehind() throws {
        let missing = sourceDir.appendingPathComponent("gone.plist")
        XCTAssertNil(WindowServerConfigBackup.snapshot(sources: [missing], into: root, label: "Desk", now: at(0)))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertEqual(leftovers, [])
    }

    func testOnlyTheNewestSnapshotsAreKept() throws {
        let system = try source("com.apple.windowserver.displays.plist")
        var folders: [String] = []
        for index in 0..<4 {
            let folder = try XCTUnwrap(WindowServerConfigBackup.snapshot(
                sources: [system], into: root, label: "Desk", now: at(Double(index) * 60), keep: 2))
            folders.append(folder.lastPathComponent)
        }
        let kept = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(kept, Array(folders.suffix(2)))
    }
}
