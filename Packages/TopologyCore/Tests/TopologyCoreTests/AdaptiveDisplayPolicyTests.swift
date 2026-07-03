import XCTest
@testable import TopologyCore

final class AdaptiveDisplayPolicyTests: XCTestCase {
    private typealias Policy = AdaptiveDisplayPolicy

    // Day 07:00, night 19:00, 30-min ramps, 0.8/0.35 plateaus, evening preset 4, hyst 0.02, cooldown 60s.
    private let config = AdaptiveDisplayConfig()
    private let noon = 720, tenPM = 1320, oneAM = 60

    private func input(now: Date = Date(timeIntervalSinceReferenceDate: 0),
                       minute: Int, builtInPresent: Bool = true, builtIn: Float? = nil,
                       asleep: Bool = false, currentPreset: Int? = nil, dayPreset: Int? = nil,
                       nightShift: Bool? = nil, sync: Bool = false, warmth: Bool = false)
        -> Policy.Input {
        Policy.Input(now: now, minuteOfDay: minute, builtInPresent: builtInPresent,
                     builtInBrightness: builtIn, displayAsleep: asleep,
                     currentPreset: currentPreset, dayPreset: dayPreset,
                     nightShiftActive: nightShift, brightnessSyncEnabled: sync,
                     warmthEnabled: warmth)
    }

    // MARK: - Schedule curve

    func testScheduleLevelDayAndNightPlateaus() {
        XCTAssertEqual(Policy.scheduleLevel(atMinute: noon, config: config), 0.8)
        XCTAssertEqual(Policy.scheduleLevel(atMinute: tenPM, config: config), 0.35)
        XCTAssertEqual(Policy.scheduleLevel(atMinute: oneAM, config: config), 0.35)  // wrapped night
    }

    func testScheduleLevelRampsLinearlyAcrossEveningTransition() {
        // 19:15 = 16/30 of the way down from 0.8 toward 0.35.
        let level = Policy.scheduleLevel(atMinute: 1155, config: config)
        XCTAssertEqual(level, 0.8 - 0.45 * (16.0 / 30.0), accuracy: 0.0001)
        // Monotonic: each ramp minute is dimmer than the last.
        let earlier = Policy.scheduleLevel(atMinute: 1150, config: config)
        XCTAssertGreaterThan(earlier, level)
        // End of ramp meets the night plateau exactly.
        XCTAssertEqual(Policy.scheduleLevel(atMinute: 1169, config: config), 0.35, accuracy: 0.0001)
    }

    func testScheduleLevelRampsLinearlyAcrossMorningTransition() {
        XCTAssertEqual(Policy.scheduleLevel(atMinute: 420, config: config),
                       0.35 + 0.45 * (1.0 / 30.0), accuracy: 0.0001)
        XCTAssertEqual(Policy.scheduleLevel(atMinute: 449, config: config), 0.8, accuracy: 0.0001)
        XCTAssertEqual(Policy.scheduleLevel(atMinute: 450, config: config), 0.8)  // plateau after ramp
    }

    func testScheduleHandlesMidnightWrappingNightStart() {
        var cfg = config
        cfg.nightStartMinute = 1430  // 23:50 — the evening ramp crosses midnight
        // 00:05 is 15 minutes into the 30-minute ramp.
        let level = Policy.scheduleLevel(atMinute: 5, config: cfg)
        XCTAssertEqual(level, 0.8 - 0.45 * (16.0 / 30.0), accuracy: 0.0001)
        XCTAssertEqual(Policy.scheduleLevel(atMinute: 120, config: cfg), 0.35)  // post-ramp night
        XCTAssertTrue(Policy.scheduleIsNight(atMinute: 0, config: cfg))
    }

    func testScheduleIsNightBoundaryEdges() {
        XCTAssertTrue(Policy.scheduleIsNight(atMinute: 1140, config: config))   // night starts AT 19:00
        XCTAssertFalse(Policy.scheduleIsNight(atMinute: 1139, config: config))
        XCTAssertTrue(Policy.scheduleIsNight(atMinute: 419, config: config))
        XCTAssertFalse(Policy.scheduleIsNight(atMinute: 420, config: config))   // day starts AT 07:00
    }

    // MARK: - Brightness sync + hysteresis

    func testSyncMirrorsBuiltInPlusOffsetClamped() {
        var state = Policy.DisplayState(brightnessOffset: 0.1)
        var decision = Policy.evaluate(input(minute: noon, builtIn: 0.5, sync: true),
                                       config: config, state: state)
        XCTAssertEqual(decision.brightnessWrite ?? -1, 0.6, accuracy: 0.0001)

        state = Policy.DisplayState(brightnessOffset: 0.2)
        decision = Policy.evaluate(input(minute: noon, builtIn: 0.95, sync: true),
                                   config: config, state: state)
        XCTAssertEqual(decision.brightnessWrite ?? -1, 1.0, accuracy: 0.0001)  // clamped
    }

    func testSyncSkipsWriteWithinHysteresis() {
        let state = Policy.DisplayState(lastWrittenBrightness: 0.60)
        let decision = Policy.evaluate(input(minute: noon, builtIn: 0.61, sync: true),
                                       config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)
        XCTAssertEqual(decision.state.lastWrittenBrightness, 0.60)  // anchor unmoved
    }

    func testSyncWritesAndAdvancesAnchorWhenCrossingHysteresis() {
        let state = Policy.DisplayState(lastWrittenBrightness: 0.60)
        let decision = Policy.evaluate(input(minute: noon, builtIn: 0.63, sync: true),
                                       config: config, state: state)
        XCTAssertEqual(decision.brightnessWrite ?? -1, 0.63, accuracy: 0.0001)
        XCTAssertEqual(decision.state.lastWrittenBrightness ?? -1, 0.63, accuracy: 0.0001)
    }

    func testBuiltInReadFailureWhilePresentSkipsTickInsteadOfScheduleFlip() {
        // Built-in is PRESENT but the sample failed: adaptive must do nothing — flipping to the
        // schedule level on a transient read hiccup would visibly yank the panel's brightness.
        let state = Policy.DisplayState(lastWrittenBrightness: 0.60)
        let decision = Policy.evaluate(input(minute: noon, builtIn: nil, sync: true),
                                       config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)
        XCTAssertEqual(decision.state, state)
    }

    func testClamshellFallsBackToScheduleLevels() {
        let decision = Policy.evaluate(
            input(minute: noon, builtInPresent: false, sync: true),
            config: config, state: Policy.DisplayState())
        XCTAssertEqual(decision.brightnessWrite ?? -1, 0.8, accuracy: 0.0001)
    }

    // MARK: - Manual override

    func testManualBrightnessLearnsOffsetAndStampsCooldown() {
        let at = Date(timeIntervalSinceReferenceDate: 100)
        let state = Policy.noteManualBrightness(0.4, builtInBrightness: 0.6, scheduleTarget: 0.8,
                                                at: at, state: Policy.DisplayState())
        XCTAssertEqual(state.brightnessOffset, -0.2, accuracy: 0.0001)
        XCTAssertEqual(state.manualBrightnessAt, at)
        XCTAssertEqual(state.lastWrittenBrightness ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertNil(state.manualScheduleAnchor)  // sync mode learns offset, not anchor
    }

    func testNoWritesDuringCooldownThenResumesWithLearnedOffset() {
        let manualAt = Date(timeIntervalSinceReferenceDate: 0)
        var state = Policy.noteManualBrightness(0.4, builtInBrightness: 0.6, scheduleTarget: 0.8,
                                                at: manualAt, state: Policy.DisplayState())
        // 30s later — inside cooldown, even though the built-in moved.
        var decision = Policy.evaluate(
            input(now: manualAt.addingTimeInterval(30), minute: noon, builtIn: 0.8, sync: true),
            config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)

        // 61s later, built-in at 0.8 → target = 0.8 + (−0.2) = 0.6: resumes at the user's level.
        state = decision.state
        decision = Policy.evaluate(
            input(now: manualAt.addingTimeInterval(61), minute: noon, builtIn: 0.8, sync: true),
            config: config, state: state)
        XCTAssertEqual(decision.brightnessWrite ?? -1, 0.6, accuracy: 0.0001)
    }

    func testManualBrightnessSetsAnchorSoResumeIssuesNoRedundantWrite() {
        let manualAt = Date(timeIntervalSinceReferenceDate: 0)
        // User set 0.4 while built-in was 0.6 (offset −0.2). Built-in unchanged after cooldown:
        // target = 0.6 − 0.2 = 0.4 == lastWritten → no pointless DDC write on resume.
        let state = Policy.noteManualBrightness(0.4, builtInBrightness: 0.6, scheduleTarget: 0.8,
                                                at: manualAt, state: Policy.DisplayState())
        let decision = Policy.evaluate(
            input(now: manualAt.addingTimeInterval(120), minute: noon, builtIn: 0.6, sync: true),
            config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)
    }

    func testScheduleModeManualAdoptsUntilTargetMovesPastHysteresis() {
        let manualAt = Date(timeIntervalSinceReferenceDate: 0)
        // Clamshell at noon (target 0.8); user dials down to 0.55.
        var state = Policy.noteManualBrightness(0.55, builtInBrightness: nil, scheduleTarget: 0.8,
                                                at: manualAt, state: Policy.DisplayState())
        XCTAssertEqual(state.manualScheduleAnchor ?? -1, 0.8, accuracy: 0.0001)

        // Hours later (cooldown long past) the schedule target is STILL 0.8 → keep the user's level.
        var decision = Policy.evaluate(
            input(now: manualAt.addingTimeInterval(7200), minute: 900, builtInPresent: false, sync: true),
            config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)

        // Evening ramp moves the target (19:10 → ~0.635) → adoption ends, adaptive resumes.
        state = decision.state
        decision = Policy.evaluate(
            input(now: manualAt.addingTimeInterval(30000), minute: 1150, builtInPresent: false, sync: true),
            config: config, state: state)
        XCTAssertNotNil(decision.brightnessWrite)
        XCTAssertNil(decision.state.manualScheduleAnchor)
    }

    // MARK: - Warmth

    func testWarmthPrefersNightShiftSignalOverSchedule() {
        // Noon (schedule says day) but Night Shift is ON → evening behavior.
        var decision = Policy.evaluate(
            input(minute: noon, currentPreset: 2, nightShift: true, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertEqual(decision.presetWrite, 4)
        XCTAssertEqual(decision.rememberDayPreset, 2)

        // 22:00 (schedule says night) but Night Shift is OFF → day behavior, restore owed preset.
        decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 4, dayPreset: 2, nightShift: false, warmth: true),
            config: config, state: Policy.DisplayState(warmthPhase: .evening))
        XCTAssertEqual(decision.presetWrite, 2)
        XCTAssertTrue(decision.clearDayPreset)
    }

    func testWarmthFallsBackToScheduleWhenNightShiftNil() {
        let decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 2, nightShift: nil, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertEqual(decision.presetWrite, 4)  // schedule says night
    }

    func testDayToEveningRemembersDayPresetThenAppliesEvening() {
        let decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertEqual(decision.rememberDayPreset, 2)  // caller persists BEFORE the write
        XCTAssertEqual(decision.presetWrite, 4)
        XCTAssertEqual(decision.state.warmthPhase, .evening)
        XCTAssertFalse(decision.clearDayPreset)
    }

    func testDayToEveningNeverOverwritesOwedDayPresetMemory() {
        // Relaunch mid-evening: fresh state (.day) but memory says day preset 2 is owed, and the
        // panel was power-cycled back to sRGB (1). The policy must re-apply evening WITHOUT
        // re-capturing — remembering "1" (or worse, the warm preset) would corrupt the restore.
        let decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 1, dayPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertNil(decision.rememberDayPreset)
        XCTAssertEqual(decision.presetWrite, 4)
        XCTAssertFalse(decision.clearDayPreset)  // owed memory intact
    }

    func testEveningToDayRestoresAndClearsDayPreset() {
        let decision = Policy.evaluate(
            input(minute: noon, currentPreset: 4, dayPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState(warmthPhase: .evening))
        XCTAssertEqual(decision.presetWrite, 2)
        XCTAssertTrue(decision.clearDayPreset)
        XCTAssertEqual(decision.state.warmthPhase, .day)
    }

    func testDayPhaseWithOwedPresetRestoresImmediately() {
        // Crash recovery: launched during the day with leftover owed memory — restore right away,
        // no phase transition needed.
        let decision = Policy.evaluate(
            input(minute: noon, currentPreset: 4, dayPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState(warmthPhase: .day))
        XCTAssertEqual(decision.presetWrite, 2)
        XCTAssertTrue(decision.clearDayPreset)
    }

    func testManualPresetDuringEveningAdoptsUntilNextTransitionThenMorningRestoreStillFires() {
        // Evening active (preset 4 applied, day preset 2 owed); user picks preset 5 manually.
        var state = Policy.DisplayState(warmthPhase: .evening)
        state = Policy.noteManualPreset(state: state)
        XCTAssertTrue(state.presetOverridden)

        // Rest of the evening: no more preset writes.
        var decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 5, dayPreset: 2, warmth: true),
            config: config, state: state)
        XCTAssertNil(decision.presetWrite)

        // Morning: the restore still fires and the adoption resets.
        state = decision.state
        decision = Policy.evaluate(
            input(minute: noon, currentPreset: 5, dayPreset: 2, warmth: true),
            config: config, state: state)
        XCTAssertEqual(decision.presetWrite, 2)
        XCTAssertTrue(decision.clearDayPreset)
        XCTAssertFalse(decision.state.presetOverridden)

        // Next evening uses the configured evening preset again (one-night adoption).
        state = decision.state
        decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 2, warmth: true),
            config: config, state: state)
        XCTAssertEqual(decision.presetWrite, 4)
    }

    func testPresetDriftFromMonitorButtonsMarksOverridden() {
        // Mid-evening the cache shows a preset we didn't apply (monitor buttons) → adopt it.
        let decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 3, dayPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState(warmthPhase: .evening))
        XCTAssertTrue(decision.state.presetOverridden)
        XCTAssertNil(decision.presetWrite)
    }

    func testCurrentPresetAlreadyEveningOwesNothing() {
        // Panel already sits on the evening preset at transition time: nothing to remember,
        // nothing to write — and critically, NO owed memory is created (a later restore would
        // otherwise "restore" the warm preset as if it were the day one).
        let decision = Policy.evaluate(
            input(minute: tenPM, currentPreset: 4, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertNil(decision.presetWrite)
        XCTAssertNil(decision.rememberDayPreset)
        XCTAssertEqual(decision.state.warmthPhase, .evening)
    }

    // MARK: - Gating

    func testAsleepDisplayProducesNoWrites() {
        let state = Policy.DisplayState(warmthPhase: .day)
        let decision = Policy.evaluate(
            input(minute: tenPM, builtIn: 0.9, asleep: true, currentPreset: 2, sync: true, warmth: true),
            config: config, state: state)
        XCTAssertNil(decision.brightnessWrite)
        XCTAssertNil(decision.presetWrite)
        XCTAssertEqual(decision.state, state)
    }

    func testDisabledFlagsAreIndependentNoOps() {
        // Both off: nothing happens despite juicy inputs.
        var decision = Policy.evaluate(
            input(minute: tenPM, builtIn: 0.9, currentPreset: 2),
            config: config, state: Policy.DisplayState())
        XCTAssertNil(decision.brightnessWrite)
        XCTAssertNil(decision.presetWrite)

        // Sync on, warmth off: brightness only.
        decision = Policy.evaluate(
            input(minute: tenPM, builtIn: 0.9, currentPreset: 2, sync: true),
            config: config, state: Policy.DisplayState())
        XCTAssertNotNil(decision.brightnessWrite)
        XCTAssertNil(decision.presetWrite)

        // Warmth on, sync off: preset only.
        decision = Policy.evaluate(
            input(minute: tenPM, builtIn: 0.9, currentPreset: 2, warmth: true),
            config: config, state: Policy.DisplayState())
        XCTAssertNil(decision.brightnessWrite)
        XCTAssertEqual(decision.presetWrite, 4)
    }
}
