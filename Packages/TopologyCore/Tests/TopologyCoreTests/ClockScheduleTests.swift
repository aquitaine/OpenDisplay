import XCTest
@testable import TopologyCore

final class ClockScheduleTests: XCTestCase {
    private typealias Policy = ClockSchedulePolicy

    private func timeEntry(minute: Int, brightness: Float,
                           transition: ScheduleTransition) -> ClockScheduleEntry {
        ClockScheduleEntry(anchor: .time, timeMinute: minute, brightness: brightness,
                           transition: transition)
    }

    // London-ish winter solstice, so solar anchors are well separated.
    private let solar = SolarEvents(sunriseMinute: 8 * 60, solarNoonMinute: 12 * 60,
                                    sunsetMinute: 16 * 60)

    // MARK: - Empty / single

    func testNoEntriesDoesNotGovern() {
        XCTAssertNil(Policy.brightness(atMinute: 600, entries: [], solar: solar))
    }

    func testSingleEntryHoldsConstantAllDay() {
        let entries = [timeEntry(minute: 9 * 60, brightness: 0.6, transition: .instant)]
        XCTAssertEqual(Policy.brightness(atMinute: 0, entries: entries, solar: nil), 0.6)
        XCTAssertEqual(Policy.brightness(atMinute: 8 * 60, entries: entries, solar: nil), 0.6)
        XCTAssertEqual(Policy.brightness(atMinute: 23 * 60, entries: entries, solar: nil), 0.6)
    }

    // MARK: - Transition styles

    func testInstantStepsAtTheAnchor() {
        let entries = [
            timeEntry(minute: 8 * 60, brightness: 0.9, transition: .instant),
            timeEntry(minute: 20 * 60, brightness: 0.3, transition: .instant),
        ]
        // Just before 20:00 we still hold the day level; exactly at 20:00 we step down.
        XCTAssertEqual(Policy.brightness(atMinute: 20 * 60 - 1, entries: entries, solar: nil), 0.9)
        XCTAssertEqual(Policy.brightness(atMinute: 20 * 60, entries: entries, solar: nil), 0.3)
        XCTAssertEqual(Policy.brightness(atMinute: 8 * 60, entries: entries, solar: nil), 0.9)
    }

    func testContinuousGlidesAcrossTheWholeGap() {
        let entries = [
            timeEntry(minute: 6 * 60, brightness: 0.2, transition: .continuous),
            timeEntry(minute: 18 * 60, brightness: 0.8, transition: .continuous),
        ]
        // Halfway between 06:00 and 18:00 (noon) → halfway between 0.2 and 0.8.
        XCTAssertEqual(try XCTUnwrap(Policy.brightness(atMinute: 12 * 60, entries: entries, solar: nil)),
                       0.5, accuracy: 0.0001)
        // A quarter of the way (09:00) → 0.2 + 0.25 * 0.6.
        XCTAssertEqual(try XCTUnwrap(Policy.brightness(atMinute: 9 * 60, entries: entries, solar: nil)),
                       0.35, accuracy: 0.0001)
    }

    func testRampHoldsThenRampsOverTheWindowEndingAtTheAnchor() throws {
        let entries = [
            timeEntry(minute: 6 * 60, brightness: 0.9, transition: .instant),
            timeEntry(minute: 20 * 60, brightness: 0.3, transition: .ramp),
        ]
        // Well before the 30-min window (19:00) we still hold the previous level.
        XCTAssertEqual(Policy.brightness(atMinute: 19 * 60, entries: entries, solar: nil), 0.9)
        // 15 minutes into the 30-minute ramp (19:45) → halfway from 0.9 to 0.3.
        XCTAssertEqual(try XCTUnwrap(Policy.brightness(atMinute: 20 * 60 - 15, entries: entries, solar: nil)),
                       0.6, accuracy: 0.0001)
        // The ramp finishes exactly at the anchor.
        XCTAssertEqual(Policy.brightness(atMinute: 20 * 60, entries: entries, solar: nil), 0.3)
    }

    // MARK: - Midnight wrap

    func testWrapsAroundMidnightBetweenLastAndFirstEntry() throws {
        let entries = [
            timeEntry(minute: 7 * 60, brightness: 0.8, transition: .continuous),
            timeEntry(minute: 22 * 60, brightness: 0.2, transition: .instant),
        ]
        // From 22:00 to 07:00 is a 9-hour wrapped gap; the first entry glides up from 0.2.
        // At 02:30 (4.5h past 22:00, halfway to 07:00) → halfway from 0.2 to 0.8.
        let value = try XCTUnwrap(Policy.brightness(atMinute: 2 * 60 + 30, entries: entries, solar: nil))
        XCTAssertEqual(value, 0.5, accuracy: 0.0001)
    }

    // MARK: - Solar anchors

    func testSolarAnchorResolvesWithOffset() {
        let entry = ClockScheduleEntry(anchor: .sunrise, offsetMinutes: -30, brightness: 0.7)
        // Sunrise 08:00, offset −30 → fires at 07:30.
        XCTAssertEqual(Policy.resolvedMinute(for: entry, solar: solar), 7 * 60 + 30)
    }

    func testSolarEntrySkippedWhenLocationUnavailable() {
        let entries = [ClockScheduleEntry(anchor: .sunset, brightness: 0.3)]
        // No solar events (no location) and only a solar entry → the schedule can't govern.
        XCTAssertNil(Policy.brightness(atMinute: 12 * 60, entries: entries, solar: nil))
    }

    func testSolarEntrySkippedDuringPolarDayButTimeEntriesStillGovern() {
        let polarSolar = SolarEvents(sunriseMinute: nil, solarNoonMinute: 12 * 60, sunsetMinute: nil)
        let entries = [
            ClockScheduleEntry(anchor: .sunset, offsetMinutes: 0, brightness: 0.2),
            timeEntry(minute: 9 * 60, brightness: 0.7, transition: .instant),
        ]
        // The sunset anchor drops out; only the 09:00 time entry remains → constant 0.7.
        XCTAssertEqual(Policy.brightness(atMinute: 15 * 60, entries: entries, solar: polarSolar), 0.7)
    }

    func testSolarNoonAnchorAlwaysAvailable() {
        let entry = ClockScheduleEntry(anchor: .solarNoon, offsetMinutes: 15, brightness: 1)
        XCTAssertEqual(Policy.resolvedMinute(for: entry, solar: solar), 12 * 60 + 15)
    }
}
