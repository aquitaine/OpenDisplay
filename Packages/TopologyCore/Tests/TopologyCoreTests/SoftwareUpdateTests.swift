import XCTest
@testable import TopologyCore

final class SoftwareUpdateTests: XCTestCase {
    private typealias Policy = SoftwareUpdatePolicy

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

    // MARK: - Release relation

    func testNewerReleaseIsNewer() {
        XCTAssertEqual(
            Policy.relation(ofAdvertised: "v0.5.0", toRunning: "0.4.1"), .newer(version: "0.5.0"))
    }

    func testDisplayVersionKeepsAPreReleaseSuffix() {
        XCTAssertEqual(
            Policy.relation(ofAdvertised: "v1.0.0-beta.2", toRunning: "0.9.0"),
            .newer(version: "1.0.0-beta.2"))
    }

    func testSameVersionIsSame() {
        XCTAssertEqual(Policy.relation(ofAdvertised: "v0.4.1", toRunning: "0.4.1"), .same)
    }

    func testDevBuildAheadOfTheFeedSeesAnOlderRelease() {
        XCTAssertEqual(Policy.relation(ofAdvertised: "v0.5.0", toRunning: "0.6.0"), .older)
    }

    func testUnparseableVersionYieldsNoRelation() {
        XCTAssertNil(Policy.relation(ofAdvertised: "latest", toRunning: "0.4.1"))
        XCTAssertNil(Policy.relation(ofAdvertised: "v0.5.0", toRunning: "dev"))
    }

    // MARK: - Downgrade guard

    func testMayInstallANewerRelease() {
        XCTAssertTrue(Policy.mayInstall(advertised: "0.9.1", running: "0.9.0"))
    }

    func testMayInstallARebuildOfTheSameVersion() {
        XCTAssertTrue(Policy.mayInstall(advertised: "0.9.0", running: "0.9.0"))
    }

    func testRefusesToInstallADowngrade() {
        XCTAssertFalse(Policy.mayInstall(advertised: "0.8.2", running: "0.9.0"))
    }

    func testDefersToTheUpdaterWhenVersionsCannotBeCompared() {
        XCTAssertTrue(Policy.mayInstall(advertised: "nightly", running: "0.9.0"))
        XCTAssertTrue(Policy.mayInstall(advertised: "0.9.1", running: "unknown"))
    }

    // MARK: - Phase machine

    func testCheckStartedShowsProgress() {
        XCTAssertEqual(Policy.phase(after: .checkStarted, from: .idle), .checking)
        XCTAssertEqual(Policy.phase(after: .checkStarted, from: .upToDate), .checking)
    }

    /// Clicking a badged row re-opens the updater's window rather than starting a fresh verdict, so
    /// the badge stays put — trading it for a spinner would strand the row when no new cycle runs.
    func testAKnownUpdateSurvivesANewCheck() {
        XCTAssertEqual(
            Policy.phase(after: .checkStarted, from: .available(version: "0.9.1")),
            .available(version: "0.9.1"))
    }

    func testAnInstallInFlightOutranksANewCheck() {
        XCTAssertEqual(Policy.phase(after: .checkStarted, from: .installing), .installing)
    }

    func testFoundUpdateBadgesTheVersion() {
        XCTAssertEqual(
            Policy.phase(after: .updateFound(version: "0.9.1"), from: .checking),
            .available(version: "0.9.1"))
    }

    func testNoUpdateFoundReportsUpToDate() {
        XCTAssertEqual(Policy.phase(after: .noUpdateFound, from: .checking), .upToDate)
    }

    func testSkippingAVersionClearsTheBadge() {
        XCTAssertEqual(
            Policy.phase(after: .updateSkipped, from: .available(version: "0.9.1")), .idle)
    }

    func testInstallationTakesOver() {
        XCTAssertEqual(
            Policy.phase(after: .installationStarted, from: .available(version: "0.9.1")), .installing)
    }

    func testACycleThatEndsWithoutAVerdictFallsBackToIdle() {
        XCTAssertEqual(Policy.phase(after: .checkFinished, from: .checking), .idle)
    }

    func testDismissingTheAlertLeavesTheUpdateBadgeStanding() {
        XCTAssertEqual(
            Policy.phase(after: .checkFinished, from: .available(version: "0.9.1")),
            .available(version: "0.9.1"))
    }

    func testAFinishedCycleDoesNotRetractAnUpToDateVerdict() {
        XCTAssertEqual(Policy.phase(after: .checkFinished, from: .upToDate), .upToDate)
    }

    func testAFinishedCycleDoesNotInterruptAnInstall() {
        XCTAssertEqual(Policy.phase(after: .checkFinished, from: .installing), .installing)
    }

    /// The whole sequence a background check that finds an update produces: the badge survives the
    /// end of the cycle, which is what makes it a reminder rather than a flash.
    func testBackgroundFindThenDismissKeepsTheBadge() {
        var phase = SoftwareUpdatePhase.idle
        for event in [SoftwareUpdateEvent.checkStarted, .updateFound(version: "1.0.0"), .checkFinished] {
            phase = Policy.phase(after: event, from: phase)
        }
        XCTAssertEqual(phase, .available(version: "1.0.0"))
    }

    /// …and the sequence an offline check produces: a spinner, then silence — never "up to date".
    func testAnOfflineCheckEndsSilently() {
        var phase = SoftwareUpdatePhase.idle
        for event in [SoftwareUpdateEvent.checkStarted, .checkFinished] {
            phase = Policy.phase(after: event, from: phase)
        }
        XCTAssertEqual(phase, .idle)
    }

    // MARK: - Presentation

    func testIdleOffersACheck() {
        let presentation = Policy.presentation(for: .idle)
        XCTAssertEqual(presentation.title, "Check for Updates…")
        XCTAssertNil(presentation.badge)
        XCTAssertFalse(presentation.showsProgress)
    }

    func testCheckingShowsProgressAndNoBadge() {
        let presentation = Policy.presentation(for: .checking)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertNil(presentation.badge)
    }

    func testAvailableBadgesTheVersion() {
        let presentation = Policy.presentation(for: .available(version: "0.9.1"))
        XCTAssertEqual(presentation.badge, "0.9.1")
        XCTAssertEqual(presentation.combinedTitle, "Update available: 0.9.1")
        XCTAssertFalse(presentation.showsProgress)
    }

    func testInstallingShowsProgress() {
        XCTAssertTrue(Policy.presentation(for: .installing).showsProgress)
    }

    func testCombinedTitleIsJustTheTitleWithoutABadge() {
        XCTAssertEqual(Policy.presentation(for: .upToDate).combinedTitle, "Up to date")
    }

    // MARK: - Automatic behaviour

    func testBothSettingsOnAllowsUnattendedInstalls() {
        let behavior = Policy.automaticBehavior(checkEnabled: true, downloadEnabled: true)
        XCTAssertTrue(behavior.checksForUpdates)
        XCTAssertTrue(behavior.downloadsAndInstalls)
    }

    func testCheckingWithoutDownloadingOnlyChecks() {
        let behavior = Policy.automaticBehavior(checkEnabled: true, downloadEnabled: false)
        XCTAssertTrue(behavior.checksForUpdates)
        XCTAssertFalse(behavior.downloadsAndInstalls)
    }

    func testDownloadPreferenceIsInertWhileAutomaticChecksAreOff() {
        let behavior = Policy.automaticBehavior(checkEnabled: false, downloadEnabled: true)
        XCTAssertFalse(behavior.checksForUpdates)
        XCTAssertFalse(behavior.downloadsAndInstalls)
    }
}
