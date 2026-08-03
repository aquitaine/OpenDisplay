import XCTest
import DisplayDomain
@testable import TopologyCore

final class LayoutProtectionPolicyTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(
        _ id: String, active: Bool = true, main: Bool = false,
        origin: DisplayOrigin = .init(x: 0, y: 0), mode: DisplayMode? = nil,
        rotation: Rotation = .degrees0, mirror: String? = nil,
        displayClass: DisplayClass = .external
    ) -> DisplayObservation {
        DisplayObservation(
            recordID: .init(rawValue: id), cgDisplayID: 1, isActive: active, origin: origin,
            mode: mode, rotation: rotation, isMain: main,
            mirrorSourceID: mirror.map { .init(rawValue: $0) },
            displayClass: displayClass, generation: .initial)
    }

    private func snap(_ observations: [DisplayObservation],
                      generation: UInt64 = 1) -> TopologySnapshot {
        TopologySnapshot(generation: .init(generation), observations: observations)
    }

    private func mode(_ width: Int, _ height: Int) -> DisplayMode {
        DisplayMode(pixelWidth: width, pixelHeight: height, pointWidth: width, pointHeight: height,
                    refreshHz: 60, isHiDPI: false)
    }

    private func context(now: Date? = nil, enabled: Bool = true,
                         asleep: Set<DisplayRecordID> = [],
                         managedOffline: Set<DisplayRecordID> = [],
                         debounce: TimeInterval = 0) -> LayoutProtectionPolicy.Context {
        LayoutProtectionPolicy.Context(
            now: now ?? epoch, isEnabled: enabled, asleepDisplayIDs: asleep,
            managedOfflineIDs: managedOffline, debounce: debounce)
    }

    /// A state already past the debounce window for `snapshot`'s generation, so a test that isn't
    /// about the debounce doesn't have to arrange one.
    private func settledState(for snapshot: TopologySnapshot) -> LayoutProtectionPolicy.State {
        LayoutProtectionPolicy.State(generation: snapshot.generation, generationFirstSeenAt: epoch)
    }

    private func decide(protected: TopologySnapshot?, current: TopologySnapshot,
                        trigger: LayoutProtectionPolicy.Trigger = .topologyChange,
                        context: LayoutProtectionPolicy.Context? = nil,
                        state: LayoutProtectionPolicy.State? = nil)
    -> LayoutProtectionPolicy.Evaluation {
        LayoutProtectionPolicy.decide(
            current: current,
            protected: protected.map { ProtectedConfig(snapshot: $0, capturedAt: epoch) },
            trigger: trigger,
            context: context ?? self.context(),
            state: state ?? settledState(for: current))
    }

    // MARK: - Display-set fingerprint

    func testFingerprintIsOrderIndependent() {
        let one = snap([obs("A", main: true), obs("B")])
        let other = snap([obs("B"), obs("A", main: true)])
        XCTAssertEqual(LayoutProtectionPolicy.fingerprint(for: one),
                       LayoutProtectionPolicy.fingerprint(for: other))
    }

    func testFingerprintSeparatesDifferentDisplaySets() {
        let laptopAlone = snap([obs("A", main: true, displayClass: .builtIn)])
        let laptopAndDesk = snap([obs("A", main: true, displayClass: .builtIn), obs("B")])
        XCTAssertNotEqual(LayoutProtectionPolicy.fingerprint(for: laptopAlone),
                          LayoutProtectionPolicy.fingerprint(for: laptopAndDesk))
    }

    func testFingerprintIgnoresTheVirtualPlaceholder() {
        let real = snap([obs("A", main: true)])
        let withPhantom = snap([obs("A", main: true), obs("phantom", displayClass: .virtual)])
        XCTAssertEqual(LayoutProtectionPolicy.fingerprint(for: withPhantom),
                       LayoutProtectionPolicy.fingerprint(for: real))
    }

    func testCaptureKeysTheLayoutUnderItsOwnDisplaySet() {
        let snapshot = snap([obs("A", main: true), obs("B")])
        let captured = LayoutProtectionPolicy.capture(snapshot, at: epoch)
        XCTAssertEqual(captured.fingerprint, LayoutProtectionPolicy.fingerprint(for: snapshot))
        XCTAssertEqual(captured.config.capturedAt, epoch)
        XCTAssertEqual(LayoutProtectionPolicy.protectedLayout(
            for: snapshot, in: [captured.fingerprint: captured.config]), captured.config)
    }

    func testCaptureDropsTheVirtualPlaceholderFromTheStoredArrangement() {
        let snapshot = snap([obs("A", main: true), obs("phantom", displayClass: .virtual)])
        let captured = LayoutProtectionPolicy.capture(snapshot, at: epoch)
        XCTAssertEqual(captured.config.snapshot.observations.map(\.recordID.rawValue), ["A"])
    }

    func testLookupMissesWhenThisDisplaySetIsNotProtected() {
        let protectedSet = snap([obs("A", main: true), obs("B")])
        let captured = LayoutProtectionPolicy.capture(protectedSet, at: epoch)
        let laptopAlone = snap([obs("A", main: true)])
        XCTAssertNil(LayoutProtectionPolicy.protectedLayout(
            for: laptopAlone, in: [captured.fingerprint: captured.config]))
    }

    // MARK: - Which drifts trigger a restore

    func testNoMatchWithoutAProtectedLayoutForThisSet() {
        let current = snap([obs("A", main: true)])
        XCTAssertEqual(decide(protected: nil, current: current).decision, .noMatch)
    }

    func testCleanWhenTheArrangementStillMatches() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B", origin: .init(x: 1920, y: 0))])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: protectedSnapshot).decision, .clean)
    }

    func testOriginDriftRestores() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B", origin: .init(x: 1920, y: 0))])
        let current = snap([obs("A", main: true), obs("B", origin: .init(x: -1920, y: 0))])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.originMoved(.init(rawValue: "B"))])))
    }

    func testModeDriftRestores() {
        let protectedSnapshot = snap([obs("A", main: true, mode: mode(2560, 1440))])
        let current = snap([obs("A", main: true, mode: mode(1920, 1080))])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.modeChanged(.init(rawValue: "A"))])))
    }

    func testRotationDriftRestores() {
        let protectedSnapshot = snap([obs("A", main: true, rotation: .degrees90)])
        let current = snap([obs("A", main: true, rotation: .degrees0)])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.rotationChanged(.init(rawValue: "A"))])))
    }

    func testMirrorDriftRestores() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        let current = snap([obs("A", main: true), obs("B", mirror: "A")])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.mirrorChanged(.init(rawValue: "B"))])))
    }

    func testMainDisplayDriftRestores() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        let current = snap([obs("A"), obs("B", main: true)])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.mainChanged(from: .init(rawValue: "A"),
                                                             to: .init(rawValue: "B"))])))
    }

    func testUnexplainedActiveChangeRestores() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        let current = snap([obs("A", main: true), obs("B", active: false)])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision,
                       .restore(.init(changes: [.activeChanged(.init(rawValue: "B"))])))
    }

    // MARK: - Never fight the managed-offline ledger

    func testActiveChangeExplainedByTheLedgerIsNotDrift() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        let current = snap([obs("A", main: true), obs("B", active: false)])
        let decision = decide(protected: protectedSnapshot, current: current,
                              context: context(managedOffline: [.init(rawValue: "B")])).decision
        XCTAssertEqual(decision, .clean)
    }

    func testLedgerExplainedDisplayStaysOffWhileOtherDriftStillRestores() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B", origin: .init(x: 1920, y: 0))])
        let current = snap([obs("A", main: true),
                            obs("B", active: false, origin: .init(x: -1920, y: 0))])
        let decision = decide(protected: protectedSnapshot, current: current,
                              context: context(managedOffline: [.init(rawValue: "B")])).decision
        XCTAssertEqual(decision, .restore(.init(changes: [.originMoved(.init(rawValue: "B"))])))
    }

    // MARK: - A different display set is a different layout

    func testAnAppearedDisplayMeansThisSetIsNoLongerTheProtectedOne() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true), obs("B")])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision, .noMatch)
    }

    func testADisconnectedDisplayMeansThisSetIsNoLongerTheProtectedOne() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        let current = snap([obs("A", main: true)])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current).decision, .noMatch)
    }

    // MARK: - Sleep counts as an active surface (0.8.2)

    func testASleepingDisplayIsNotTreatedAsTurnedOff() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B")])
        // What the OS reports for a sleeping panel: inactive, but still online and still there.
        let current = snap([obs("A", main: true), obs("B", active: false)])
        let decision = decide(protected: protectedSnapshot, current: current,
                              context: context(asleep: [.init(rawValue: "B")])).decision
        XCTAssertEqual(decision, .clean)
    }

    func testASleepingDisplayStillRestoresItsOtherDrift() {
        let protectedSnapshot = snap([obs("A", main: true), obs("B", origin: .init(x: 1920, y: 0))])
        let current = snap([obs("A", main: true),
                            obs("B", active: false, origin: .init(x: -1920, y: 0))])
        let decision = decide(protected: protectedSnapshot, current: current,
                              context: context(asleep: [.init(rawValue: "B")])).decision
        XCTAssertEqual(decision, .restore(.init(changes: [.originMoved(.init(rawValue: "B"))])))
    }

    // MARK: - Anti-fight guard: the master toggle

    func testProtectionOffIgnoresEverything() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))])
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current,
                              context: context(enabled: false)).decision,
                       .ignore(.protectionDisabled))
    }

    // MARK: - Anti-fight guard: self-change suppression

    func testOurOwnWriteNeverTriggersARestore() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 7)
        var state = settledState(for: current)
        state = LayoutProtectionPolicy.noteSelfChange(generation: current.generation, state: state)
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current, state: state).decision,
                       .ignore(.selfChange))
    }

    func testSuppressionAppliesOnlyToTheGenerationOurWriteRaised() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let ourWrite = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 7)
        var state = settledState(for: ourWrite)
        state = LayoutProtectionPolicy.noteSelfChange(generation: ourWrite.generation, state: state)
        let somebodyElse = snap([obs("A", main: true, origin: .init(x: 200, y: 0))], generation: 8)
        let evaluation = decide(protected: protectedSnapshot, current: somebodyElse, state: state)
        XCTAssertEqual(evaluation.decision, .restore(.init(changes: [.originMoved(.init(rawValue: "A"))])))
    }

    func testALandedRestoreSuppressesTheGenerationItsOwnWritesRaised() {
        let state = LayoutProtectionPolicy.noteRestoreOutcome(
            before: .init(4), after: .init(5), state: LayoutProtectionPolicy.State())
        XCTAssertEqual(state.suppressedGeneration, .init(5))
    }

    func testARestoreThatChangedNothingLeavesTheRetryPathOpen() {
        var state = LayoutProtectionPolicy.State()
        state.suppressedGeneration = .init(4)
        let after = LayoutProtectionPolicy.noteRestoreOutcome(before: .init(4), after: .init(4),
                                                             state: state)
        XCTAssertNil(after.suppressedGeneration, "a restore that didn't land must not silence itself")
    }

    // MARK: - Anti-fight guard: debounce

    func testDriftIsIgnoredUntilTheTopologyHasBeenQuiet() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 2)
        let evaluation = decide(protected: protectedSnapshot, current: current,
                                context: context(now: epoch, debounce: 3),
                                state: LayoutProtectionPolicy.State())
        XCTAssertEqual(evaluation.decision, .ignore(.debouncing))
        XCTAssertEqual(evaluation.recheckAfter, 3)
    }

    func testDebounceRecheckShrinksAsTheWindowElapses() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 2)
        let state = LayoutProtectionPolicy.State(generation: current.generation,
                                                 generationFirstSeenAt: epoch)
        let evaluation = decide(protected: protectedSnapshot, current: current,
                                context: context(now: epoch.addingTimeInterval(1), debounce: 3),
                                state: state)
        XCTAssertEqual(evaluation.decision, .ignore(.debouncing))
        XCTAssertEqual(evaluation.recheckAfter ?? 0, 2, accuracy: 0.001)
    }

    func testDriftRestoresOnceTheDebounceWindowHasElapsed() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 2)
        let state = LayoutProtectionPolicy.State(generation: current.generation,
                                                 generationFirstSeenAt: epoch)
        let evaluation = decide(protected: protectedSnapshot, current: current,
                                context: context(now: epoch.addingTimeInterval(3), debounce: 3),
                                state: state)
        XCTAssertEqual(evaluation.decision, .restore(.init(changes: [.originMoved(.init(rawValue: "A"))])))
        XCTAssertNil(evaluation.recheckAfter)
    }

    func testANewGenerationRestartsTheDebounceWindow() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let settled = LayoutProtectionPolicy.State(generation: .init(2), generationFirstSeenAt: epoch)
        let hotplug = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 3)
        let evaluation = decide(protected: protectedSnapshot, current: hotplug,
                                context: context(now: epoch.addingTimeInterval(30), debounce: 3),
                                state: settled)
        XCTAssertEqual(evaluation.decision, .ignore(.debouncing))
    }

    // MARK: - Anti-fight guard: retry cap

    func testRestoreAttemptsAreCappedPerGenerationAndReportedOnce() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 2)
        var state = settledState(for: current)

        for _ in 0..<2 {
            let evaluation = decide(protected: protectedSnapshot, current: current, state: state)
            guard case .restore = evaluation.decision else {
                return XCTFail("expected a restore while attempts remain")
            }
            XCTAssertFalse(evaluation.shouldNotifyFailure)
            state = LayoutProtectionPolicy.noteRestoreAttempt(state: evaluation.state)
        }

        let givenUp = decide(protected: protectedSnapshot, current: current, state: state)
        XCTAssertEqual(givenUp.decision, .ignore(.retryCapReached))
        XCTAssertTrue(givenUp.shouldNotifyFailure)

        let again = decide(protected: protectedSnapshot, current: current, state: givenUp.state)
        XCTAssertEqual(again.decision, .ignore(.retryCapReached))
        XCTAssertFalse(again.shouldNotifyFailure, "the give-up notice fires once, not per event")
    }

    func testTheRetryCapDoesNotFireWhenTheLayoutIsAlreadyClean() {
        let protectedSnapshot = snap([obs("A", main: true)], generation: 2)
        var state = settledState(for: protectedSnapshot)
        state.restoreAttempts = 2
        XCTAssertEqual(decide(protected: protectedSnapshot, current: protectedSnapshot,
                              state: state).decision, .clean)
    }

    func testANewGenerationRefreshesTheAttemptBudget() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 3)
        var state = LayoutProtectionPolicy.State(generation: .init(2), generationFirstSeenAt: epoch)
        state.restoreAttempts = 2
        let evaluation = decide(protected: protectedSnapshot, current: current, state: state)
        XCTAssertEqual(evaluation.decision, .restore(.init(changes: [.originMoved(.init(rawValue: "A"))])))
        XCTAssertEqual(evaluation.state.restoreAttempts, 0)
    }

    func testWakeRefreshesTheAttemptBudgetForAnUnchangedGeneration() {
        let protectedSnapshot = snap([obs("A", main: true)])
        let current = snap([obs("A", main: true, origin: .init(x: 100, y: 0))], generation: 2)
        var state = settledState(for: current)
        state.restoreAttempts = 2
        state.hasNotifiedFailure = true
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current, state: state).decision,
                       .ignore(.retryCapReached))
        XCTAssertEqual(decide(protected: protectedSnapshot, current: current, trigger: .wake,
                              state: state).decision,
                       .restore(.init(changes: [.originMoved(.init(rawValue: "A"))])))
    }

    // MARK: - Restore plan + copy

    func testRestoreSceneAssertsTheCapturedArrangementWithOptionalMembers() {
        let protectedSnapshot = snap([
            obs("A", main: true, origin: .init(x: 0, y: 0), mode: mode(2560, 1440)),
            obs("B", origin: .init(x: 2560, y: 0), rotation: .degrees90)
        ])
        let scene = LayoutProtectionPolicy.restoreScene(
            for: ProtectedConfig(snapshot: protectedSnapshot, capturedAt: epoch))
        XCTAssertEqual(scene.id, LayoutProtectionPolicy.restoreSceneID)
        XCTAssertEqual(scene.members.map(\.selector), ["id:A", "id:B"])
        XCTAssertTrue(scene.members.allSatisfy { !$0.required })
        XCTAssertEqual(scene.members[0].desired.main, true)
        XCTAssertEqual(scene.members[0].desired.mode, mode(2560, 1440))
        XCTAssertEqual(scene.members[1].desired.position, DisplayOrigin(x: 2560, y: 0))
        XCTAssertEqual(scene.members[1].desired.rotation, .degrees90)
        XCTAssertEqual(scene.members[1].desired.connected, true)
    }

    func testSummaryNamesEachDisplayAndTheFieldsThatMoved() {
        let analysis = DisplayConfigDrifter.DriftAnalysis(changes: [
            .originMoved(.init(rawValue: "B")),
            .modeChanged(.init(rawValue: "B")),
            .mainChanged(from: .init(rawValue: "A"), to: .init(rawValue: "B"))
        ])
        let summary = LayoutProtectionPolicy.summary(
            of: analysis, names: [.init(rawValue: "B"): "Desk"])
        XCTAssertEqual(summary, "Desk: position, resolution · main display")
    }

    func testSummaryFallsBackToTheRecordIDForAnUnnamedDisplay() {
        let analysis = DisplayConfigDrifter.DriftAnalysis(changes: [.rotationChanged(.init(rawValue: "B"))])
        XCTAssertEqual(LayoutProtectionPolicy.summary(of: analysis, names: [:]), "B: rotation")
    }

    func testRestoreNotificationCarriesTheChangedFieldsAndRespectsTheToggle() {
        let analysis = DisplayConfigDrifter.DriftAnalysis(changes: [.originMoved(.init(rawValue: "B"))])
        let names: [DisplayRecordID: String] = [.init(rawValue: "B"): "Desk"]
        let note = LayoutProtectionPolicy.restoreNotification(for: analysis, names: names, enabled: true)
        XCTAssertEqual(note?.title, "Restored your protected layout")
        XCTAssertEqual(note?.body, "Desk: position")
        XCTAssertNil(LayoutProtectionPolicy.restoreNotification(for: analysis, names: names, enabled: false))
    }

    func testFailureNotificationSaysWhatToDoNextAndRespectsTheToggle() {
        let note = LayoutProtectionPolicy.failureNotification(enabled: true)
        XCTAssertEqual(note?.title, "Couldn\u{2019}t restore your protected layout")
        XCTAssertTrue(note?.body.contains("Protect the current layout again") == true)
        XCTAssertNil(LayoutProtectionPolicy.failureNotification(enabled: false))
    }

    func testChangeNamesTheDisplayItIsAbout() {
        XCTAssertEqual(DisplayConfigDrifter.Change.originMoved(.init(rawValue: "B")).displayID,
                       .init(rawValue: "B"))
        XCTAssertEqual(DisplayConfigDrifter.Change
            .mainChanged(from: .init(rawValue: "A"), to: .init(rawValue: "B")).displayID,
                       .init(rawValue: "B"))
    }
}
