import XCTest
@testable import TopologyCore

final class XDRPowerAutomationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let boost: Float = 0.45

    /// An automation whose boost the user engaged at `now`. Rules aren't held by the policy — every
    /// `evaluate` reads them live — so they're passed at the call site instead.
    private func engaged() -> XDRPowerAutomation {
        var automation = XDRPowerAutomation()
        automation.noteUserSet(fraction: boost, at: now)
        return automation
    }

    // MARK: - Rule 1: on battery

    func testGoingOnBatterySuspendsTheBoost() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        let decision = automation.evaluate(
            rules: rules, power: .init(onBattery: true, batteryPercent: 90),
            boostFraction: boost, builtInActive: true, now: now)
        XCTAssertEqual(decision, .suspend(reason: .onBattery))
        XCTAssertEqual(automation.suspendedFraction, boost)  // remembered for the restore
    }

    func testBatteryRuleOffLeavesTheBoostAlone() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: false)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(
            rules: rules, power: .init(onBattery: true, batteryPercent: 5),
            boostFraction: boost, builtInActive: true, now: now), .none)
    }

    func testEvaluatingTwiceOnBatteryDoesNotReFire() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        let power = XDRPowerAutomation.PowerSnapshot(onBattery: true, batteryPercent: 90)
        XCTAssertEqual(automation.evaluate(rules: rules, power: power, boostFraction: boost,
                                           builtInActive: true, now: now), .suspend(reason: .onBattery))
        // The host has zeroed the boost, so the second pass sees no fraction — and must sit still.
        XCTAssertEqual(automation.evaluate(rules: rules, power: power, boostFraction: 0,
                                           builtInActive: true, now: now), .none)
    }

    // MARK: - Rule 2: low-battery cutoff

    func testCutoffFiresAtOrBelowTheThresholdOnly() {
        let rules = XDRPowerAutomation.Rules(lowBatteryCutoffPercent: 20)
        var above = engaged()
        XCTAssertEqual(above.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 21),
                                      boostFraction: boost, builtInActive: true, now: now), .none)
        var at = engaged()
        XCTAssertEqual(at.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 20),
                                   boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .lowBattery(percent: 20)))
        var below = engaged()
        XCTAssertEqual(below.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 8),
                                      boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .lowBattery(percent: 8)))
    }

    func testCutoffWorksWithoutTheOnBatteryRule() {
        // The two rules are independent: a user can allow the boost on battery until charge is low.
        let rules = XDRPowerAutomation.Rules(disableOnBattery: false, lowBatteryCutoffPercent: 30)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 12),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .lowBattery(percent: 12)))
    }

    func testCutoffIsIgnoredOnWallPowerAndWithAnUnreadableCharge() {
        let rules = XDRPowerAutomation.Rules(lowBatteryCutoffPercent: 50)
        // Charging at 5% is not a reason to drop the boost — the cutoff is a battery rule.
        var plugged = engaged()
        XCTAssertEqual(plugged.evaluate(rules: rules, power: .init(onBattery: false, batteryPercent: 5),
                                        boostFraction: boost, builtInActive: true, now: now), .none)
        // A desktop (or a snapshot taken mid-change) reports no percentage: never guess it's low.
        var unreadable = engaged()
        XCTAssertEqual(unreadable.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: nil),
                                           boostFraction: boost, builtInActive: true, now: now), .none)
    }

    // MARK: - Rule 3: Low Power Mode

    func testLowPowerModeSuspendsAndClearingItRestores() {
        let rules = XDRPowerAutomation.Rules(disableInLowPowerMode: true)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(lowPowerMode: true),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .lowPowerMode))
        // Low Power Mode is a condition, not an event: switching it off gives the boost back, even
        // on battery, because no other battery-family rule is armed.
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, lowPowerMode: false),
                                           boostFraction: 0, builtInActive: true, now: now),
                       .restore(fraction: boost))
    }

    func testLowPowerModeRuleOffIsInert() {
        let rules = XDRPowerAutomation.Rules(disableInLowPowerMode: false)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(lowPowerMode: true),
                                           boostFraction: boost, builtInActive: true, now: now), .none)
    }

    // MARK: - Precedence and combinations

    func testOnBatteryIsReportedAheadOfTheCutoffAndLowPowerMode() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, lowBatteryCutoffPercent: 50,
                                             disableInLowPowerMode: true)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(
            rules: rules, power: .init(onBattery: true, batteryPercent: 10, lowPowerMode: true),
            boostFraction: boost, builtInActive: true, now: now), .suspend(reason: .onBattery))
    }

    func testABatteryConditionOutranksAnElapsedTimer() {
        // Both apply; reporting the recoverable one means plugging in still puts the boost back.
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, autoOffMinutes: 15)
        var automation = engaged()
        let later = now.addingTimeInterval(60 * 60)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 80),
                                           boostFraction: boost, builtInActive: true, now: later),
                       .suspend(reason: .onBattery))
        XCTAssertEqual(automation.suspendedFraction, boost)
    }

    func testRestoreWaitsUntilEveryBatteryConditionIsClear() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, disableInLowPowerMode: true)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 60),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .onBattery))
        // Back on wall power, but Low Power Mode is still on — still a reason to stay off.
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: false, lowPowerMode: true),
                                           boostFraction: 0, builtInActive: true, now: now), .none)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0, builtInActive: true, now: now),
                       .restore(fraction: boost))
    }

    // MARK: - Rule 5: restore

    func testRestoreRoundTripsTheExactFractionAndFiresOnce() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = XDRPowerAutomation()
        automation.noteUserSet(fraction: 0.73, at: now)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 88),
                                           boostFraction: 0.73, builtInActive: true, now: now),
                       .suspend(reason: .onBattery))
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0, builtInActive: true, now: now),
                       .restore(fraction: 0.73))
        // The host has re-applied it; a second pass in the same conditions must not re-fire.
        XCTAssertNil(automation.suspendedFraction)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0.73, builtInActive: true, now: now), .none)
    }

    func testRestoreIsBlockedWhenTheUserSetTheBoostMeanwhile() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 40),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .onBattery))
        // The user moves the slider while still on battery: their choice replaces what we owed.
        automation.noteUserSet(fraction: 0.2, at: now.addingTimeInterval(30))
        XCTAssertNil(automation.suspendedFraction)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0.2, builtInActive: true, now: now), .none)
    }

    func testUserTurningTheBoostOffCancelsTheOwedRestore() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        _ = automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 40),
                                boostFraction: boost, builtInActive: true, now: now)
        automation.noteUserSet(fraction: 0, at: now.addingTimeInterval(5))
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0, builtInActive: true, now: now), .none)
    }

    func testRestoreDisabledLeavesTheBoostOffForever() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, restoreOnPower: false)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 40),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .onBattery))
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower,
                                           boostFraction: 0, builtInActive: true, now: now), .none)
    }

    func testTurningTheRuleOffWhileSuspendedGivesTheBoostBack() {
        var rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        let power = XDRPowerAutomation.PowerSnapshot(onBattery: true, batteryPercent: 40)
        XCTAssertEqual(automation.evaluate(rules: rules, power: power, boostFraction: boost,
                                           builtInActive: true, now: now), .suspend(reason: .onBattery))
        rules.disableOnBattery = false  // the rule holding the screen dim is switched off
        XCTAssertEqual(automation.evaluate(rules: rules, power: power, boostFraction: 0,
                                           builtInActive: true, now: now), .restore(fraction: boost))
    }

    // MARK: - Rule 4: auto-off timer

    func testTimerFiresAtTheDeadlineAndNotBefore() {
        let rules = XDRPowerAutomation.Rules(autoOffMinutes: 30)
        var automation = engaged()
        let deadline = now.addingTimeInterval(30 * 60)
        XCTAssertEqual(automation.autoOffDeadline(rules: rules), deadline)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: deadline.addingTimeInterval(-1)), .none)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: deadline),
                       .suspend(reason: .autoOffTimer))
    }

    func testTimerNeverRestores() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, autoOffMinutes: 15)
        var automation = engaged()
        let later = now.addingTimeInterval(20 * 60)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: later),
                       .suspend(reason: .autoOffTimer))
        XCTAssertNil(automation.suspendedFraction)  // an elapsed allowance isn't owed back
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: 0,
                                           builtInActive: true, now: later.addingTimeInterval(60)), .none)
        XCTAssertNil(automation.autoOffDeadline(rules: rules))  // and nothing is armed any more
    }

    func testTimerRestartsWhenTheUserSetsTheBoostAgain() {
        let rules = XDRPowerAutomation.Rules(autoOffMinutes: 60)
        var automation = engaged()
        let elapsed = now.addingTimeInterval(90 * 60)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: elapsed),
                       .suspend(reason: .autoOffTimer))
        automation.noteUserSet(fraction: boost, at: elapsed)
        XCTAssertEqual(automation.autoOffDeadline(rules: rules), elapsed.addingTimeInterval(60 * 60))
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: elapsed.addingTimeInterval(60)), .none)
    }

    func testARestoredBoostStartsTheTimerAfresh() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true, autoOffMinutes: 15)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 70),
                                           boostFraction: boost, builtInActive: true, now: now),
                       .suspend(reason: .onBattery))
        let backOnPower = now.addingTimeInterval(60 * 60)  // suspended for an hour, well past 15 min
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: 0,
                                           builtInActive: true, now: backOnPower),
                       .restore(fraction: boost))
        // The restored boost gets its full allowance rather than expiring on the next pass.
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true, now: backOnPower.addingTimeInterval(60)),
                       .none)
        XCTAssertEqual(automation.autoOffDeadline(rules: rules),
                       backOnPower.addingTimeInterval(15 * 60))
    }

    func testNoTimerRuleMeansNoDeadlineAndNoExpiry() {
        let rules = XDRPowerAutomation.Rules(autoOffMinutes: nil)
        var automation = engaged()
        XCTAssertNil(automation.autoOffDeadline(rules: rules))
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: true,
                                           now: now.addingTimeInterval(60 * 60 * 24)), .none)
    }

    // MARK: - Rule 6: the built-in going away

    func testBuiltInGoingInactiveClearsTheBoostWithoutRemembering() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: boost,
                                           builtInActive: false, now: now),
                       .suspend(reason: .builtInInactive))
        XCTAssertNil(automation.suspendedFraction)
        // And it stays off when the panel comes back — a boost never survives its own display.
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: 0,
                                           builtInActive: true, now: now.addingTimeInterval(60)), .none)
    }

    func testTheBuiltInLeavingWhileSuspendedDropsTheOwedRestore() {
        let rules = XDRPowerAutomation.Rules(disableOnBattery: true)
        var automation = engaged()
        _ = automation.evaluate(rules: rules, power: .init(onBattery: true, batteryPercent: 40),
                                boostFraction: boost, builtInActive: true, now: now)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: 0,
                                           builtInActive: false, now: now), .none)
        XCTAssertNil(automation.suspendedFraction)
        XCTAssertEqual(automation.evaluate(rules: rules, power: .onWallPower, boostFraction: 0,
                                           builtInActive: true, now: now), .none)
    }

    // MARK: - Wiring hints the host relies on

    func testOnlyBatteryFamilyRulesAskForPowerMonitoring() {
        XCTAssertFalse(XDRPowerAutomation.Rules().needsPowerMonitoring)
        XCTAssertFalse(XDRPowerAutomation.Rules(autoOffMinutes: 30).needsPowerMonitoring)
        XCTAssertTrue(XDRPowerAutomation.Rules(disableOnBattery: true).needsPowerMonitoring)
        XCTAssertTrue(XDRPowerAutomation.Rules(lowBatteryCutoffPercent: 10).needsPowerMonitoring)
        XCTAssertTrue(XDRPowerAutomation.Rules(disableInLowPowerMode: true).needsPowerMonitoring)
    }

    func testEveryPowerReasonNotifiesAndTheLidCloseStaysSilent() {
        XCTAssertNotNil(XDRPowerAutomation.SuspensionReason.onBattery.notificationBody)
        XCTAssertEqual(XDRPowerAutomation.SuspensionReason.lowBattery(percent: 18).notificationBody,
                       "Battery at 18%.")
        XCTAssertNotNil(XDRPowerAutomation.SuspensionReason.lowPowerMode.notificationBody)
        XCTAssertNotNil(XDRPowerAutomation.SuspensionReason.autoOffTimer.notificationBody)
        XCTAssertNil(XDRPowerAutomation.SuspensionReason.builtInInactive.notificationBody)
        XCTAssertTrue(XDRPowerAutomation.SuspensionReason.lowPowerMode.isBatteryFamily)
        XCTAssertFalse(XDRPowerAutomation.SuspensionReason.autoOffTimer.isBatteryFamily)
        XCTAssertFalse(XDRPowerAutomation.SuspensionReason.builtInInactive.isBatteryFamily)
    }
}
