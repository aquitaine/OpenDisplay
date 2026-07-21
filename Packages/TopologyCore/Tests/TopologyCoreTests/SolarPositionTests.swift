import XCTest
@testable import TopologyCore

/// Solar math validated against published NOAA/almanac sunrise-sunset pairs for known city/date
/// combinations, plus construction-guaranteed invariants (noon symmetry, polar day/night). The
/// tolerance is a couple of minutes — the horizon-refraction model and rounding differ slightly
/// between sources.
final class SolarPositionTests: XCTestCase {
    private let toleranceMinutes = 3

    private func events(latitude: Double, longitude: Double, year: Int, month: Int, day: Int,
                        utcOffsetMinutes: Int) -> SolarEvents {
        SolarCalculator.events(year: year, month: month, day: day,
                               coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                               utcOffsetMinutes: utcOffsetMinutes)
    }

    func testLondonWinterSolstice() throws {
        // London (Greenwich), 2024-12-21, GMT: sunrise ~08:04, solar noon ~11:58, sunset ~15:53.
        let solar = events(latitude: 51.4769, longitude: 0.0,
                           year: 2024, month: 12, day: 21, utcOffsetMinutes: 0)
        XCTAssertEqual(try XCTUnwrap(solar.sunriseMinute), 8 * 60 + 4, accuracy: toleranceMinutes)
        XCTAssertEqual(solar.solarNoonMinute, 11 * 60 + 58, accuracy: toleranceMinutes)
        XCTAssertEqual(try XCTUnwrap(solar.sunsetMinute), 15 * 60 + 53, accuracy: toleranceMinutes)
    }

    func testNewYorkSummerSolstice() throws {
        // NYC, 2024-06-20 (solstice), EDT (UTC−4): sunrise ~05:24, sunset ~20:31.
        let solar = events(latitude: 40.7128, longitude: -74.0060,
                           year: 2024, month: 6, day: 20, utcOffsetMinutes: -240)
        XCTAssertEqual(try XCTUnwrap(solar.sunriseMinute), 5 * 60 + 24, accuracy: toleranceMinutes)
        XCTAssertEqual(try XCTUnwrap(solar.sunsetMinute), 20 * 60 + 31, accuracy: toleranceMinutes)
    }

    func testSydneyMidWinter() throws {
        // Sydney, 2024-06-21, AEST (UTC+10): sunrise ~07:00, sunset ~16:54 (southern hemisphere).
        let solar = events(latitude: -33.8688, longitude: 151.2093,
                           year: 2024, month: 6, day: 21, utcOffsetMinutes: 600)
        XCTAssertEqual(try XCTUnwrap(solar.sunriseMinute), 7 * 60, accuracy: toleranceMinutes)
        XCTAssertEqual(try XCTUnwrap(solar.sunsetMinute), 16 * 60 + 54, accuracy: toleranceMinutes)
    }

    func testSunriseAndSunsetAreSymmetricAboutSolarNoon() throws {
        // A construction invariant independent of any ephemeris source: noon bisects the daylight arc.
        let solar = events(latitude: 37.7749, longitude: -122.4194,
                           year: 2024, month: 9, day: 22, utcOffsetMinutes: -420)
        let sunrise = try XCTUnwrap(solar.sunriseMinute)
        let sunset = try XCTUnwrap(solar.sunsetMinute)
        XCTAssertEqual((sunrise + sunset) / 2, solar.solarNoonMinute, accuracy: 1)
    }

    func testPolarNightHasNoSunriseOrSunset() {
        // Tromsø, 2024-12-21: the sun stays below the horizon all day.
        let solar = events(latitude: 69.6492, longitude: 18.9553,
                           year: 2024, month: 12, day: 21, utcOffsetMinutes: 60)
        XCTAssertNil(solar.sunriseMinute)
        XCTAssertNil(solar.sunsetMinute)
    }

    func testPolarDayHasNoSunriseOrSunset() {
        // Tromsø, 2024-06-21: the midnight sun never sets.
        let solar = events(latitude: 69.6492, longitude: 18.9553,
                           year: 2024, month: 6, day: 21, utcOffsetMinutes: 120)
        XCTAssertNil(solar.sunriseMinute)
        XCTAssertNil(solar.sunsetMinute)
    }

    func testDaylightSavingOffsetIsHonouredViaTimeZone() throws {
        // The Date/TimeZone convenience must apply the zone's summer offset for the date.
        var newYorkCalendar = Calendar(identifier: .gregorian)
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        newYorkCalendar.timeZone = newYork
        let solsticeNoon = try XCTUnwrap(
            newYorkCalendar.date(from: DateComponents(year: 2024, month: 6, day: 20, hour: 12)))
        let solar = SolarCalculator.events(
            on: solsticeNoon, in: newYork,
            coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.0060))
        XCTAssertEqual(try XCTUnwrap(solar.sunriseMinute), 5 * 60 + 24, accuracy: toleranceMinutes)
    }
}
