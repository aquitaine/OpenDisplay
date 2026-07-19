import XCTest
@testable import TopologyCore

final class UpdateCheckTests: XCTestCase {
    // MARK: - SemanticVersion parsing

    func testParsesPlainVersion() {
        let v = SemanticVersion("0.4.1")
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 4)
        XCTAssertEqual(v?.patch, 1)
    }

    func testParsesLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion("1.2.3"))
        XCTAssertEqual(SemanticVersion("V1.2.3"), SemanticVersion("1.2.3"))
    }

    func testMissingComponentsDefaultToZero() {
        XCTAssertEqual(SemanticVersion("1"), SemanticVersion("1.0.0"))
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion("1.2.0"))
    }

    func testStripsPreReleaseAndBuildSuffix() {
        XCTAssertEqual(SemanticVersion("0.5.0-beta.1"), SemanticVersion("0.5.0"))
        XCTAssertEqual(SemanticVersion("0.5.0+42"), SemanticVersion("0.5.0"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1..3"))
        XCTAssertNil(SemanticVersion("1.-2.3"))
    }

    func testOrdering() {
        XCTAssertLessThan(SemanticVersion("0.4.1")!, SemanticVersion("0.5.0")!)
        XCTAssertLessThan(SemanticVersion("0.9.9")!, SemanticVersion("1.0.0")!)
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("1.0.1")!)
        XCTAssertFalse(SemanticVersion("1.0.0")! < SemanticVersion("1.0.0")!)
    }

    // MARK: - Availability

    func testNewerTagIsAvailable() {
        let result = UpdateCheckPolicy.availability(
            current: "0.4.1", latestTag: "v0.5.0", releaseURL: "https://example.com/r")
        XCTAssertEqual(result, .available(version: "0.5.0", url: "https://example.com/r"))
    }

    func testSameVersionIsUpToDate() {
        XCTAssertEqual(
            UpdateCheckPolicy.availability(current: "0.4.1", latestTag: "v0.4.1", releaseURL: "u"),
            .upToDate)
    }

    func testDevBuildAheadOfLatestReleaseIsUpToDate() {
        XCTAssertEqual(
            UpdateCheckPolicy.availability(current: "0.6.0", latestTag: "v0.5.0", releaseURL: "u"),
            .upToDate)
    }

    func testUnparseableTagYieldsNoDecision() {
        XCTAssertNil(UpdateCheckPolicy.availability(current: "0.4.1", latestTag: "latest", releaseURL: "u"))
        XCTAssertNil(UpdateCheckPolicy.availability(current: "dev", latestTag: "v0.5.0", releaseURL: "u"))
    }

    // MARK: - Auto-check throttle

    func testNeverCheckedIsDue() {
        XCTAssertTrue(UpdateCheckPolicy.shouldAutoCheck(lastCheck: nil, now: Date()))
    }

    func testRecentCheckIsNotDue() {
        let now = Date()
        XCTAssertFalse(UpdateCheckPolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(-3600), now: now))
    }

    func testCheckOlderThanIntervalIsDue() {
        let now = Date()
        XCTAssertTrue(UpdateCheckPolicy.shouldAutoCheck(
            lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    func testFutureLastCheckIsDue() {
        let now = Date()
        XCTAssertTrue(UpdateCheckPolicy.shouldAutoCheck(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    func testCustomInterval() {
        let now = Date()
        XCTAssertTrue(UpdateCheckPolicy.shouldAutoCheck(
            lastCheck: now.addingTimeInterval(-120), now: now, minimumInterval: 60))
        XCTAssertFalse(UpdateCheckPolicy.shouldAutoCheck(
            lastCheck: now.addingTimeInterval(-30), now: now, minimumInterval: 60))
    }
}
