import XCTest
import DisplayDomain
@testable import TopologyCore

/// The wake the user reported, decided as a table: externals still asleep, a built-in macOS relit
/// on its own, and a safety net that must never conclude from either that the Mac has no screens.
final class WakeConvergencePolicyTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func obs(_ id: String, active: Bool = true,
                     displayClass: DisplayClass = .external) -> DisplayObservation {
        DisplayObservation(recordID: .init(rawValue: id), cgDisplayID: 1, isActive: active,
                           displayClass: displayClass, generation: .initial)
    }

    private func offline(_ id: String,
                         displayClass: DisplayClass = .builtIn,
                         stamped: Bool = false) -> ManagedOfflineDisplay {
        ManagedOfflineDisplay(recordID: .init(rawValue: id), cgID: 7, name: id,
                              displayClass: displayClass,
                              relitDuringWakeAt: stamped ? epoch.addingTimeInterval(-60) : nil)
    }

    private func context(_ observations: [DisplayObservation],
                         offline managedOffline: [ManagedOfflineDisplay] = [],
                         wokeSecondsAgo: TimeInterval? = nil,
                         midTransition: Bool = false,
                         darkForSeconds: TimeInterval? = nil,
                         attempts: [DisplayRecordID: Int] = [:]) -> WakeConvergencePolicy.Context {
        WakeConvergencePolicy.Context(
            now: epoch, observations: observations, managedOffline: managedOffline,
            lastWakeAt: wokeSecondsAgo.map { epoch.addingTimeInterval(-$0) },
            isBetweenSleepAndWake: midTransition,
            darkSince: darkForSeconds.map { epoch.addingTimeInterval(-$0) },
            reassertAttempts: attempts)
    }

    /// macOS's stand-in for "no displays at all" — active, main, and showing nothing.
    private var phantom: DisplayObservation { obs("phantom", displayClass: .virtual) }

    // MARK: - What counts as a screen

    func testASleepingPanelIsStillASurface() {
        // The observer folds sleep into `isActive` (0.8.2); a merely idle Mac is not a dark one.
        XCTAssertEqual(WakeConvergencePolicy.visibleSurfaces(in: [obs("A")]).count, 1)
    }

    func testThePhantomIsNotASurface() {
        XCTAssertTrue(WakeConvergencePolicy.visibleSurfaces(in: [phantom]).isEmpty)
    }

    // MARK: - Rule 1: the always-one-active safety net

    func testALitDisplayNeedsNoRescue() {
        XCTAssertEqual(WakeConvergencePolicy.surfaceDecision(context([obs("A")])), .satisfied)
    }

    /// The 0.8.2 case, unchanged: the last external is unplugged while the built-in is logically
    /// off, macOS substitutes its placeholder, and the built-in comes straight back.
    func testUnpluggingTheLastExternalRestoresTheBuiltInImmediately() {
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom], offline: [offline("builtin")]))
        XCTAssertEqual(decision, .restore(offline("builtin")))
    }

    /// The regression this whole change exists to stop. A wake looks exactly like an unplug for the
    /// second or two an external needs to re-negotiate its link, and firing into that window lit the
    /// built-in the user had deliberately turned off.
    func testAWakeIsWaitedOutRatherThanRescued() {
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom], offline: [offline("builtin")], wokeSecondsAgo: 1, darkForSeconds: 1))
        XCTAssertEqual(decision, .waitForWakingDisplay(WakeConvergencePolicy.defaultRecheckStep))
    }

    /// An external macOS still enumerates while nothing is lit is a panel finishing its handshake,
    /// wake or no wake.
    func testAnEnumeratedButUnlitExternalIsWaitedFor() {
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([obs("ext", active: false)], offline: [offline("builtin")], darkForSeconds: 1))
        XCTAssertEqual(decision, .waitForWakingDisplay(WakeConvergencePolicy.defaultRecheckStep))
    }

    /// …but the ledger's own displays don't count as "on their way back". The public provider turns
    /// a display off by MIRRORING it, so it stays enumerated and dark indefinitely — waiting on that
    /// would stall the net at exactly the moment it is needed.
    func testTheDisplayWeTurnedOffIsNotMistakenForOneComingBack() {
        let mirroredOff = obs("builtin", active: false, displayClass: .builtIn)
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([mirroredOff, phantom], offline: [offline("builtin")], darkForSeconds: 1))
        XCTAssertEqual(decision, .restore(offline("builtin")))
    }

    /// The guarantee is delayed, never traded away: whatever the display list claims, a dark Mac
    /// gets a screen back inside the deadline.
    func testWaitingIsBoundedSoADarkMacAlwaysGetsAScreen() {
        let deadline = WakeConvergencePolicy.defaultRecoveryDeadline
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom], offline: [offline("builtin")],
                    wokeSecondsAgo: 1, darkForSeconds: deadline))
        XCTAssertEqual(decision, .restore(offline("builtin")))
    }

    func testTheLastRecheckNeverOverrunsTheDeadline() {
        let deadline = WakeConvergencePolicy.defaultRecoveryDeadline
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom], offline: [offline("builtin")],
                    wokeSecondsAgo: 1, darkForSeconds: deadline - 0.1))
        guard case .waitForWakingDisplay(let delay) = decision else {
            return XCTFail("expected one last short wait, got \(decision)")
        }
        XCTAssertEqual(delay, 0.1, accuracy: 0.001,
                       "the final wait must land on the deadline, never past it")
    }

    func testTheBuiltInIsPreferredAsTheEmergencyScreen() {
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom],
                    offline: [offline("ext", displayClass: .external), offline("builtin")]))
        XCTAssertEqual(decision, .restore(offline("builtin")))
    }

    func testWithNoBuiltInTheMostRecentlyTurnedOffDisplayIsUsed() {
        let older = offline("ext-1", displayClass: .external)
        let newer = offline("ext-2", displayClass: .external)
        XCTAssertEqual(WakeConvergencePolicy.surfaceDecision(context([phantom],
                                                                    offline: [older, newer])),
                       .restore(newer))
    }

    func testNothingLitAndNothingOwedIsStranded() {
        XCTAssertEqual(WakeConvergencePolicy.surfaceDecision(context([phantom])), .stranded)
    }

    // MARK: - Rule 2: forgetting a ledger entry, or not

    func testADisplayReEnabledElsewhereIsForgotten() {
        // No wake in play: someone switched it on in System Settings, so stop owing it an "off".
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")]))
        XCTAssertEqual(forget, [.init(rawValue: "builtin")])
    }

    /// The heart of the reported bug: the same observation, moments after a wake, means macOS relit
    /// the panel — and this entry is the only record that an "off" is still owed.
    func testADisplayMacOSRelitOnWakeIsNotForgotten() {
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertTrue(forget.isEmpty)
    }

    /// The race that would have made all of this a coin toss: reconfiguration events arrive while
    /// the machine is coming back but before macOS posts `didWake`, so `lastWakeAt` is still the
    /// wake before last (or nil). The sleep half of the pair is what covers that gap.
    func testADisplayThatComesBackBeforeMacOSSaysTheMachineWokeIsNotForgotten() {
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")], wokeSecondsAgo: 40_000, midTransition: true))
        XCTAssertTrue(forget.isEmpty)
    }

    /// The same gap, seen by the safety net: an unplug-shaped display list mid-transition is a wake
    /// in progress, not a reason to light the built-in.
    func testTheSafetyNetWaitsThroughTheSleepWakeGapToo() {
        let decision = WakeConvergencePolicy.surfaceDecision(
            context([phantom], offline: [offline("builtin")],
                    midTransition: true, darkForSeconds: 1))
        XCTAssertEqual(decision, .waitForWakingDisplay(WakeConvergencePolicy.defaultRecheckStep))
    }

    func testTheWakeWindowEventuallyClosesAndTheEntryIsForgotten() {
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")],
                    wokeSecondsAgo: WakeConvergencePolicy.defaultWakeWindow))
        XCTAssertEqual(forget, [.init(rawValue: "builtin")])
    }

    func testAStillDarkLedgerDisplayIsNeverForgotten() {
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("ext")], offline: [offline("builtin")]))
        XCTAssertTrue(forget.isEmpty)
    }

    // MARK: - Rule 2: the wake's stamp, which carries the owed "off" past the window

    /// The relight is attributed while the window can still tell whose doing it was — and only
    /// then. Outside the window a lit ledger display means the user, and gets no stamp.
    func testAVisibleLedgerDisplayIsStampedInsideTheWakeAndOnlyThere() {
        let world = { (wokeSecondsAgo: TimeInterval) in
            self.context([self.obs("builtin", displayClass: .builtIn)],
                         offline: [self.offline("builtin")], wokeSecondsAgo: wokeSecondsAgo)
        }
        XCTAssertEqual(WakeConvergencePolicy.entriesToStampRelit(world(2)),
                       [.init(rawValue: "builtin")])
        XCTAssertTrue(WakeConvergencePolicy.entriesToStampRelit(
            world(WakeConvergencePolicy.defaultWakeWindow)).isEmpty)
    }

    func testAStillDarkLedgerDisplayGetsNoStamp() {
        let stamp = WakeConvergencePolicy.entriesToStampRelit(
            context([obs("ext")], offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertTrue(stamp.isEmpty)
    }

    func testAnAlreadyStampedEntryIsNotStampedAgain() {
        let stamp = WakeConvergencePolicy.entriesToStampRelit(
            context([obs("builtin", displayClass: .builtIn)],
                    offline: [offline("builtin", stamped: true)], wokeSecondsAgo: 2))
        XCTAssertTrue(stamp.isEmpty)
    }

    /// The reported bug, second edition: the external lit only after the user's thumbprint, well
    /// past the 20-second window, and the window closing had *erased* the owed "off" — the built-in
    /// stayed glowing next to the ultrawide for the rest of the session. A stamped entry is never
    /// forgotten for being visible, however long ago the window closed.
    func testAStampedEntryOutlivesTheWakeWindow() {
        let forget = WakeConvergencePolicy.entriesToForget(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin", stamped: true)],
                    wokeSecondsAgo: 300))
        XCTAssertTrue(forget.isEmpty)
    }

    /// …and when the external finally does light, the "off" is paid — minutes after the window
    /// would have given up.
    func testAStampedEntryIsPutBackOffWheneverTheExternalFinallyLights() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin", stamped: true)],
                    wokeSecondsAgo: 300))
        XCTAssertEqual(intent.reassert, [offline("builtin", stamped: true)])
        XCTAssertNil(intent.recheckAfter)
    }

    /// While the covering display is still missing, the pending wait slows to the long step:
    /// nothing bounds a lock screen, and the activation's own topology event is what normally
    /// answers first anyway.
    func testAStampedEntryWaitsAtTheSlowerPendingPaceOutsideTheWindow() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn)],
                    offline: [offline("builtin", stamped: true)],
                    wokeSecondsAgo: 300))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertEqual(intent.recheckAfter, WakeConvergencePolicy.defaultPendingRecheckStep)
    }

    /// The attempts cap is about flicker, not clocks — it binds a stamped entry the same way.
    func testAStampedEntryStillRespectsTheAttemptsCap() {
        let spent = [DisplayRecordID(rawValue: "builtin"):
                        WakeConvergencePolicy.defaultMaximumReassertAttempts]
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin", stamped: true)],
                    wokeSecondsAgo: 300, attempts: spent))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertNil(intent.recheckAfter)
    }

    /// A ledger of old, never-stamped format entries behaves exactly as before the stamp existed.
    func testAnOldFormatLedgerEntryDecodesWithoutAStamp() throws {
        let json = #"[{"recordID":{"rawValue":"cg:X"},"cgID":3,"name":"P","displayClass":"builtIn"}]"#
        let decoded = try JSONDecoder().decode([ManagedOfflineDisplay].self,
                                               from: Data(json.utf8))
        XCTAssertNil(decoded.first?.relitDuringWakeAt)
    }

    // MARK: - Rule 2: putting the relit display back off

    /// The whole point, end to end: the built-in came back with the machine, an external is lit to
    /// take over, so the built-in goes away again.
    func testARelitBuiltInIsPutBackOffOnceAnExternalIsLit() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertEqual(intent.reassert, [offline("builtin")])
        XCTAssertNil(intent.recheckAfter)
    }

    /// Rule 1 outranks rule 2 and is not argued with: while the relit built-in is the ONLY screen,
    /// the answer is "ask again", never "turn it off".
    func testTheOnlyLitScreenIsNeverTheOneWeTurnOff() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn)],
                    offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertEqual(intent.recheckAfter, WakeConvergencePolicy.defaultReassertRecheckStep)
    }

    /// The placeholder is never a screen, so it can never be what "covers" a display going off:
    /// turning the built-in off against it would leave the user with macOS's stand-in and nothing
    /// they can actually see.
    func testThePhantomCannotCoverADisplayGoingOff() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), phantom],
                    offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertEqual(intent.recheckAfter, WakeConvergencePolicy.defaultReassertRecheckStep)
    }

    func testNothingIsOwedOutsideAWake() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")]))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertNil(intent.recheckAfter)
    }

    func testALedgerDisplayThatStayedOffIsNotTouched() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("ext")], offline: [offline("builtin")], wokeSecondsAgo: 2))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertNil(intent.recheckAfter)
    }

    /// macOS can insist. Two tries per wake, then let it be — a tug-of-war the user watches flicker
    /// is worse than a display that stayed on.
    func testTheReassertGivesUpAfterItsAttemptsAreSpent() {
        let spent = [DisplayRecordID(rawValue: "builtin"):
                        WakeConvergencePolicy.defaultMaximumReassertAttempts]
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("ext")],
                    offline: [offline("builtin")], wokeSecondsAgo: 2, attempts: spent))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertNil(intent.recheckAfter)
    }

    func testEveryOwedDisplayIsPutBackOffWhenARealScreenCoversThem() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("spare"), obs("ext")],
                    offline: [offline("builtin"), offline("spare", displayClass: .external)],
                    wokeSecondsAgo: 2))
        XCTAssertEqual(intent.reassert.map(\.recordID.rawValue), ["builtin", "spare"])
    }

    /// Two ledger displays lit and nothing else: turning both off would go dark, so neither moves
    /// until a display the ledger doesn't own is back.
    func testLedgerDisplaysAloneCannotCoverEachOther() {
        let intent = WakeConvergencePolicy.offlineIntent(
            context([obs("builtin", displayClass: .builtIn), obs("spare")],
                    offline: [offline("builtin"), offline("spare", displayClass: .external)],
                    wokeSecondsAgo: 2))
        XCTAssertTrue(intent.reassert.isEmpty)
        XCTAssertEqual(intent.recheckAfter, WakeConvergencePolicy.defaultReassertRecheckStep)
    }

    // MARK: - The audit trail

    /// The reported gap: a wake re-assert switched the built-in off with nothing in audit.jsonl to
    /// say so. Every wake-convergence write now records who (the distinct actor) and what.
    func testAReassertIsAuditedUnderItsOwnActorAndCommand() {
        let entry = WakeConvergencePolicy.reassertAudit(of: offline("builtin"), committed: true,
                                                        at: epoch)
        XCTAssertEqual(entry.actor, .wakeConvergence)
        XCTAssertEqual(entry.command, "reassertOff")
        XCTAssertEqual(entry.transactionId, "txn_reassertOff")
        XCTAssertEqual(entry.status, "committed")
        XCTAssertEqual(entry.targets, ["builtin"])
        XCTAssertEqual(entry.timestamp, epoch)
    }

    /// A refused disconnect is not silently dropped from history — it lands as "failed".
    func testAFailedReassertIsAuditedAsFailed() {
        let entry = WakeConvergencePolicy.reassertAudit(of: offline("builtin"), committed: false,
                                                        at: epoch)
        XCTAssertEqual(entry.status, "failed")
    }

    func testTheNetLightingItsFallbackIsAudited() {
        let entry = WakeConvergencePolicy.netActivateAudit(of: offline("builtin"), committed: true,
                                                           at: epoch)
        XCTAssertEqual(entry.actor, .wakeConvergence)
        XCTAssertEqual(entry.command, "netActivate")
        XCTAssertEqual(entry.transactionId, "txn_netActivate")
        XCTAssertEqual(entry.status, "committed")
        XCTAssertEqual(entry.targets, ["builtin"])
    }

    func testAFailedNetActivationIsAuditedAsFailed() {
        let entry = WakeConvergencePolicy.netActivateAudit(of: offline("builtin"), committed: false,
                                                           at: epoch)
        XCTAssertEqual(entry.status, "failed")
    }

    /// The escalation is system-wide (the public permanent-config restore names no display) and
    /// reports no outcome, so its entry says exactly that: no targets, status "attempted".
    func testTheNetEscalationIsAuditedWithoutTargets() {
        let entry = WakeConvergencePolicy.netEscalateAudit(at: epoch)
        XCTAssertEqual(entry.actor, .wakeConvergence)
        XCTAssertEqual(entry.command, "netEscalate")
        XCTAssertEqual(entry.transactionId, "txn_netEscalate")
        XCTAssertEqual(entry.status, "attempted")
        XCTAssertEqual(entry.targets, [])
    }
}
