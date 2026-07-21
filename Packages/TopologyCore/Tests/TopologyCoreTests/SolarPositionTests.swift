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

    // MARK: - Sun elevation (Issue #31: Location Mode)

    /// Elevations validated against `astral` (Michalsky 1988), an algorithm independent of the NOAA
    /// equations this file implements. The two sources agree within a couple hundredths of a degree
    /// at high sun and within half a degree near the horizon, where refraction modelling differs
    /// most — well inside the ~0.5° tolerance Location Mode's curve needs.
    private let toleranceDegrees = 0.5

    private func elevation(latitude: Double, longitude: Double, year: Int, month: Int, day: Int,
                           minute: Int, utcOffsetMinutes: Int) -> Double {
        SolarCalculator.elevationDegrees(
            atMinute: minute, year: year, month: month, day: day,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            utcOffsetMinutes: utcOffsetMinutes)
    }

    func testElevationNewYorkSummerSolsticeNoon() {
        // NYC, 2024-06-21, 12:00 EDT (UTC−4): astral gives 68.8727°.
        let sunElevation = elevation(latitude: 40.7128, longitude: -74.0060,
                                     year: 2024, month: 6, day: 21, minute: 12 * 60,
                                     utcOffsetMinutes: -240)
        XCTAssertEqual(sunElevation, 68.8727, accuracy: toleranceDegrees)
    }

    func testElevationLondonEquinoxNoon() {
        // London, 2024-03-20, 12:00 GMT (UTC+0): astral gives 38.6334°.
        let sunElevation = elevation(latitude: 51.5074, longitude: -0.1278,
                                     year: 2024, month: 3, day: 20, minute: 12 * 60,
                                     utcOffsetMinutes: 0)
        XCTAssertEqual(sunElevation, 38.6334, accuracy: toleranceDegrees)
    }

    func testElevationSydneySummerSolsticeNoon() {
        // Sydney, 2024-12-21, 12:00 AEDT (UTC+11): astral gives 74.3695° (southern summer).
        let sunElevation = elevation(latitude: -33.8688, longitude: 151.2093,
                                     year: 2024, month: 12, day: 21, minute: 12 * 60,
                                     utcOffsetMinutes: 660)
        XCTAssertEqual(sunElevation, 74.3695, accuracy: toleranceDegrees)
    }

    func testElevationTokyoWinterMorning() {
        // Tokyo, 2024-01-15, 08:00 JST (UTC+9): astral gives 11.2694° — a low mid-morning sun.
        let sunElevation = elevation(latitude: 35.6762, longitude: 139.6503,
                                     year: 2024, month: 1, day: 15, minute: 8 * 60,
                                     utcOffsetMinutes: 540)
        XCTAssertEqual(sunElevation, 11.2694, accuracy: toleranceDegrees)
    }

    func testElevationNearHorizonAtDusk() {
        // San Francisco, 2024-09-22, 19:00 PDT (UTC−7): astral gives 0.7152° — just above the
        // horizon, the regime where the NOAA and Michalsky refraction models diverge most.
        let sunElevation = elevation(latitude: 37.7749, longitude: -122.4194,
                                     year: 2024, month: 9, day: 22, minute: 19 * 60,
                                     utcOffsetMinutes: -420)
        XCTAssertEqual(sunElevation, 0.7152, accuracy: toleranceDegrees)
    }

    func testElevationIsNegativeAtMidnight() {
        // The sun is well below the horizon at local midnight regardless of season or latitude.
        let sunElevation = elevation(latitude: 37.7749, longitude: -122.4194,
                                     year: 2024, month: 9, day: 22, minute: 0, utcOffsetMinutes: -420)
        XCTAssertLessThan(sunElevation, -30)
    }

    func testElevationRisesThroughMorningAndPeaksNearSolarNoon() {
        // Construction invariant independent of any ephemeris source: elevation climbs from
        // sunrise toward solar noon, then descends — monotonic on each side of the peak.
        let coordinate = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)
        let solar = SolarCalculator.events(year: 2024, month: 9, day: 22, coordinate: coordinate,
                                           utcOffsetMinutes: -420)
        let morningElevation = elevation(latitude: 37.7749, longitude: -122.4194,
                                         year: 2024, month: 9, day: 22, minute: 9 * 60,
                                         utcOffsetMinutes: -420)
        let noonElevation = elevation(latitude: 37.7749, longitude: -122.4194,
                                      year: 2024, month: 9, day: 22, minute: solar.solarNoonMinute,
                                      utcOffsetMinutes: -420)
        let afternoonElevation = elevation(latitude: 37.7749, longitude: -122.4194,
                                           year: 2024, month: 9, day: 22, minute: 15 * 60,
                                           utcOffsetMinutes: -420)
        XCTAssertLessThan(morningElevation, noonElevation)
        XCTAssertLessThan(afternoonElevation, noonElevation)
    }
}
