import XCTest
@testable import TopologyCore

final class AppPresetPolicyTests: XCTestCase {
    private typealias Policy = AppPresetPolicy

    private let epoch = Date(timeIntervalSinceReferenceDate: 0)
    private let externalOne = "cgid:1"
    private let externalTwo = "cgid:2"

    private func figmaPreset(target: Policy.Target = .allDisplays,
                             brightness: Float? = 0.6, contrast: Float? = nil,
                             colorPreset: Int? = nil) -> Policy.AppPreset {
        Policy.AppPreset(bundleIdentifier: "com.figma.Desktop", applicationName: "Figma",
                         brightness: brightness, contrast: contrast, colorPreset: colorPreset,
                         target: target)
    }

    private func snapshot(_ recordID: String, brightness: Float? = nil, contrast: Float? = nil,
                          colorPreset: Int? = nil) -> Policy.DisplaySnapshot {
        Policy.DisplaySnapshot(recordID: recordID, brightness: brightness, contrast: contrast,
                               colorPreset: colorPreset)
    }

    /// Drives `resolve` twice at the same instant then once past the debounce window, threading the
    /// returned state — the standard way a settled switch commits in these tests.
    private func settle(frontmost: String?, presets: [Policy.AppPreset],
                        displays: [Policy.DisplaySnapshot], from state: Policy.ActivationState,
                        debounce: TimeInterval = Policy.defaultDebounce) -> Policy.Decision {
        let opening = Policy.resolve(
            Policy.Input(frontmostBundleID: frontmost, now: epoch, presets: presets,
                         displays: displays, debounce: debounce), state: state)
        return Policy.resolve(
            Policy.Input(frontmostBundleID: frontmost, now: epoch.addingTimeInterval(debounce),
                         presets: presets, displays: displays, debounce: debounce),
            state: opening.state)
    }

    // MARK: - Activation

    func testSettlingOnAConfiguredAppCapturesTheLivePriorStateAndWritesThePreset() {
        let decision = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                              displays: [snapshot(externalOne, brightness: 0.9)],
                              from: Policy.ActivationState())
        XCTAssertTrue(decision.appPresetIsActive)
        XCTAssertEqual(decision.state.activeBundleID, "com.figma.Desktop")
        XCTAssertEqual(decision.captures[externalOne], Policy.PriorState(brightness: 0.9))
        XCTAssertEqual(decision.applyWrites, [Policy.DisplayWrite(recordID: externalOne, brightness: 0.6)])
        XCTAssertTrue(decision.restoreWrites.isEmpty)
    }

    func testActivationOnlyCapturesTheChannelsThePresetActuallyWrites() {
        let preset = figmaPreset(brightness: 0.5, contrast: nil, colorPreset: 4)
        let decision = settle(frontmost: "com.figma.Desktop", presets: [preset],
                              displays: [snapshot(externalOne, brightness: 0.8, contrast: 0.7,
                                                  colorPreset: 1)],
                              from: Policy.ActivationState())
        XCTAssertEqual(decision.captures[externalOne],
                       Policy.PriorState(brightness: 0.8, contrast: nil, colorPreset: 1))
        XCTAssertEqual(decision.applyWrites,
                       [Policy.DisplayWrite(recordID: externalOne, brightness: 0.5, colorPreset: 4)])
    }

    // MARK: - Restore

    func testLeavingTheAppRestoresTheOwedPriorStateAndClearsTheLedger() {
        let activated = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                               displays: [snapshot(externalOne, brightness: 0.9)],
                               from: Policy.ActivationState())
        let decision = settle(frontmost: "com.apple.Finder", presets: [figmaPreset()],
                              displays: [snapshot(externalOne, brightness: 0.6)],
                              from: activated.state)
        XCTAssertFalse(decision.appPresetIsActive)
        XCTAssertNil(decision.state.activeBundleID)
        XCTAssertEqual(decision.restoreWrites, [Policy.DisplayWrite(recordID: externalOne, brightness: 0.9)])
        XCTAssertEqual(decision.clears, [externalOne])
        XCTAssertTrue(decision.state.priorStateByDisplay.isEmpty)
    }

    func testAFrontmostAppWithNoConfiguredPresetDeactivates() {
        let activated = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                               displays: [snapshot(externalOne, brightness: 0.9)],
                               from: Policy.ActivationState())
        let decision = settle(frontmost: "com.unknown.App", presets: [figmaPreset()],
                              displays: [snapshot(externalOne, brightness: 0.6)],
                              from: activated.state)
        XCTAssertNil(decision.state.activeBundleID)
        XCTAssertEqual(decision.restoreWrites.map(\.recordID), [externalOne])
    }

    // MARK: - Debounce (injectable clock)

    func testRapidSwitchingWithinTheDebounceWindowIssuesNoWrites() {
        let presets = [figmaPreset()]
        let displays = [snapshot(externalOne, brightness: 0.9)]
        let first = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.figma.Desktop", now: epoch, presets: presets,
                         displays: displays), state: Policy.ActivationState())
        XCTAssertTrue(first.applyWrites.isEmpty)
        XCTAssertEqual(first.rescheduleAfter, Policy.defaultDebounce)

        // Another app grabs the front 0.1s later — still inside the window, still no hardware write.
        let second = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.apple.Finder", now: epoch.addingTimeInterval(0.1),
                         presets: presets, displays: displays), state: first.state)
        XCTAssertTrue(second.applyWrites.isEmpty)
        XCTAssertTrue(second.restoreWrites.isEmpty)
        XCTAssertNil(second.state.activeBundleID)
        XCTAssertEqual(second.state.pendingBundleID, nil)  // Finder has no preset → desired is nil
    }

    func testTheSwitchCommitsOnlyAfterTheFrontStaysPutPastTheWindow() {
        let presets = [figmaPreset()]
        let displays = [snapshot(externalOne, brightness: 0.9)]
        let opening = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.figma.Desktop", now: epoch, presets: presets,
                         displays: displays), state: Policy.ActivationState())
        let stillWaiting = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.figma.Desktop", now: epoch.addingTimeInterval(0.2),
                         presets: presets, displays: displays), state: opening.state)
        XCTAssertTrue(stillWaiting.applyWrites.isEmpty)
        XCTAssertEqual(stillWaiting.rescheduleAfter ?? 0, Policy.defaultDebounce - 0.2, accuracy: 0.001)

        let committed = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.figma.Desktop", now: epoch.addingTimeInterval(0.4),
                         presets: presets, displays: displays), state: stillWaiting.state)
        XCTAssertEqual(committed.applyWrites, [Policy.DisplayWrite(recordID: externalOne, brightness: 0.6)])
        XCTAssertNil(committed.rescheduleAfter)
    }

    // MARK: - App-to-app switching

    func testSwitchingBetweenTwoAppsRestoresNonSharedDisplaysAndKeepsTheTrueBaselineOnShared() {
        let figma = Policy.AppPreset(bundleIdentifier: "com.figma.Desktop", applicationName: "Figma",
                                     brightness: 0.6, target: .allDisplays)
        let terminal = Policy.AppPreset(bundleIdentifier: "com.apple.Terminal",
                                        applicationName: "Terminal", brightness: 0.3,
                                        target: .display("cgid:1"))
        let displays = [snapshot(externalOne, brightness: 0.9), snapshot(externalTwo, brightness: 0.8)]
        let onFigma = settle(frontmost: "com.figma.Desktop", presets: [figma, terminal],
                             displays: displays, from: Policy.ActivationState())
        // Figma owns both displays at baseline (0.9, 0.8). Now Terminal (external one only) takes over.
        let onTerminal = settle(frontmost: "com.apple.Terminal", presets: [figma, terminal],
                                displays: displays, from: onFigma.state)
        // External two leaves the active set → restored to its true baseline 0.8 and cleared.
        XCTAssertEqual(onTerminal.restoreWrites, [Policy.DisplayWrite(recordID: externalTwo, brightness: 0.8)])
        XCTAssertEqual(onTerminal.clears, [externalTwo])
        // External one keeps its baseline (0.9, not Figma's applied 0.6) and gets Terminal's value.
        XCTAssertTrue(onTerminal.captures.isEmpty)
        XCTAssertEqual(onTerminal.applyWrites, [Policy.DisplayWrite(recordID: externalOne, brightness: 0.3)])
        XCTAssertEqual(onTerminal.state.priorStateByDisplay[externalOne], Policy.PriorState(brightness: 0.9))
    }

    // MARK: - Targeting

    func testASpecificDisplayTargetGovernsOnlyThatDisplay() {
        let preset = figmaPreset(target: .display("cgid:2"))
        let decision = settle(frontmost: "com.figma.Desktop", presets: [preset],
                              displays: [snapshot(externalOne, brightness: 0.9),
                                         snapshot(externalTwo, brightness: 0.8)],
                              from: Policy.ActivationState())
        XCTAssertEqual(decision.applyWrites.map(\.recordID), [externalTwo])
    }

    func testATargetDisplayThatIsAbsentProducesNoWrite() {
        let preset = figmaPreset(target: .display("cgid:9"))
        let decision = settle(frontmost: "com.figma.Desktop", presets: [preset],
                              displays: [snapshot(externalOne, brightness: 0.9)],
                              from: Policy.ActivationState())
        XCTAssertTrue(decision.applyWrites.isEmpty)
        XCTAssertTrue(decision.captures.isEmpty)
    }

    // MARK: - Topology churn while active

    func testAnUnpluggedDisplaysLedgerEntryStaysOwedWhenTheAppLeaves() {
        let displays = [snapshot(externalOne, brightness: 0.9), snapshot(externalTwo, brightness: 0.8)]
        let activated = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                               displays: displays, from: Policy.ActivationState())
        // External two is unplugged, then the user leaves Figma. Its restore write couldn't land,
        // so its ledger entry must stay owed — clearing it would strand the display at the preset
        // value forever once re-plugged.
        let decision = settle(frontmost: "com.apple.Finder", presets: [figmaPreset()],
                              displays: [snapshot(externalOne, brightness: 0.6)],
                              from: activated.state)
        XCTAssertEqual(decision.restoreWrites.map(\.recordID), [externalOne])
        XCTAssertEqual(decision.clears, [externalOne])
        XCTAssertEqual(decision.state.priorStateByDisplay[externalTwo], Policy.PriorState(brightness: 0.8))
    }

    func testADisplayArrivingMidActivationIsGovernedWithoutAnAppSwitch() {
        let activated = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                               displays: [snapshot(externalOne, brightness: 0.9)],
                               from: Policy.ActivationState())
        // External two plugs in while Figma stays frontmost: the steady re-evaluation (kicked by the
        // caller's topology observer) must capture + apply it, not wait for the next app switch.
        let decision = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.figma.Desktop", now: epoch.addingTimeInterval(60),
                         presets: [figmaPreset()],
                         displays: [snapshot(externalOne, brightness: 0.6),
                                    snapshot(externalTwo, brightness: 0.8)]),
            state: activated.state)
        XCTAssertEqual(decision.captures, [externalTwo: Policy.PriorState(brightness: 0.8)])
        XCTAssertEqual(decision.applyWrites, [Policy.DisplayWrite(recordID: externalTwo, brightness: 0.6)])
        XCTAssertTrue(decision.restoreWrites.isEmpty)  // external one is already governed — no rewrite
        XCTAssertTrue(decision.appPresetIsActive)
    }

    func testAReturningDisplayIsRestoredWhenNoPresetIsActive() {
        // An owed entry survived an unplug (see above) and the app has since deactivated. When the
        // display returns, the steady no-preset state must pay the restore back — not hold it until quit.
        let owed = Policy.ActivationState(priorStateByDisplay: [externalTwo: Policy.PriorState(brightness: 0.8)])
        let decision = Policy.resolve(
            Policy.Input(frontmostBundleID: "com.apple.Finder", now: epoch, presets: [figmaPreset()],
                         displays: [snapshot(externalTwo, brightness: 0.6)]),
            state: owed)
        XCTAssertEqual(decision.restoreWrites, [Policy.DisplayWrite(recordID: externalTwo, brightness: 0.8)])
        XCTAssertEqual(decision.clears, [externalTwo])
        XCTAssertTrue(decision.state.priorStateByDisplay.isEmpty)
    }

    // MARK: - Crash safety

    func testTheBaselineIsCapturedBeforeTheApplyWriteSoACrashBetweenStillOwesARestore() {
        // The Decision carries `captures` (persist-before-write) separately from `applyWrites`, and the
        // final ledger already owes the baseline — so a crash after persisting captures but before the
        // apply write lands still restores the true prior state on relaunch.
        let decision = settle(frontmost: "com.figma.Desktop", presets: [figmaPreset()],
                              displays: [snapshot(externalOne, brightness: 0.9)],
                              from: Policy.ActivationState())
        XCTAssertEqual(decision.captures[externalOne], Policy.PriorState(brightness: 0.9))
        XCTAssertEqual(decision.state.priorStateByDisplay[externalOne], Policy.PriorState(brightness: 0.9))
    }

    // MARK: - Persistence

    func testAppPresetRoundTripsThroughJSON() throws {
        let preset = Policy.AppPreset(bundleIdentifier: "com.figma.Desktop", applicationName: "Figma",
                                      brightness: 0.6, contrast: 0.5, colorPreset: 4,
                                      target: .display("cgid:1"))
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Policy.AppPreset.self, from: encoded)
        XCTAssertEqual(decoded, preset)
    }

    func testPriorStateRoundTripsThroughJSON() throws {
        let prior = Policy.PriorState(brightness: 0.42, contrast: 0.73, colorPreset: 2)
        let encoded = try JSONEncoder().encode(prior)
        let decoded = try JSONDecoder().decode(Policy.PriorState.self, from: encoded)
        XCTAssertEqual(decoded, prior)
    }
}
