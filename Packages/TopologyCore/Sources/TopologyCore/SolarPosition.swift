import Foundation

/// A point on Earth in degrees: latitude positive north, longitude positive east.
public struct GeoCoordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Sunrise, solar noon, and sunset for one calendar day at a location, expressed as minutes-of-day
/// in that location's local (wall-clock) time. Sunrise/sunset are nil when the sun stays entirely
/// below the horizon (polar night) or entirely above it (polar day); solar noon is always defined.
public struct SolarEvents: Hashable, Sendable {
    public var sunriseMinute: Int?
    public var solarNoonMinute: Int
    public var sunsetMinute: Int?

    public init(sunriseMinute: Int?, solarNoonMinute: Int, sunsetMinute: Int?) {
        self.sunriseMinute = sunriseMinute
        self.solarNoonMinute = solarNoonMinute
        self.sunsetMinute = sunsetMinute
    }
}

/// Pure, deterministic solar-position math using the public-domain NOAA solar equations. No
/// Calendar/timezone lookups inside the core arithmetic: the caller passes the calendar date and the
/// location's UTC offset in minutes, so the result is exactly reproducible and unit-testable against
/// published ephemeris. Accuracy is within about a minute for non-polar latitudes.
public enum SolarCalculator {
    /// The sunrise/sunset solar zenith in degrees: 90.833° folds in atmospheric refraction at the
    /// horizon (~34′) plus the sun's own angular radius (~16′), the standard NOAA convention.
    private static let sunriseZenithDegrees = 90.833

    /// Solar events for a `Date` in a `TimeZone`, honouring that zone's UTC offset on that day (so
    /// daylight-saving transitions are handled correctly). The offset is resolved at that civil
    /// day's noon, not at `date` itself: queried at 00:30 on a DST-transition day, the instant's
    /// offset is the pre-shift one, which would report sunrise/sunset an hour off — noon is safely
    /// past every real-world transition (02:00–03:00) and matches the offset in effect at the
    /// events themselves.
    public static func events(on date: Date, in timeZone: TimeZone,
                              coordinate: GeoCoordinate) -> SolarEvents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let noon = calendar.date(from: DateComponents(
            year: dayComponents.year, month: dayComponents.month, day: dayComponents.day, hour: 12
        )) ?? date
        return events(year: dayComponents.year ?? 2000,
                      month: dayComponents.month ?? 1,
                      day: dayComponents.day ?? 1,
                      coordinate: coordinate,
                      utcOffsetMinutes: timeZone.secondsFromGMT(for: noon) / 60)
    }

    /// Solar events for an explicit calendar date and UTC offset — the deterministic core the tests
    /// pin against known city/date ephemeris.
    public static func events(year: Int, month: Int, day: Int,
                              coordinate: GeoCoordinate, utcOffsetMinutes: Int) -> SolarEvents {
        let julianDay = julianDay(year: year, month: month, day: day)
        // Evaluate at local solar noon (NOAA spreadsheet method) for best single-pass accuracy.
        let localNoonDayFraction = (720.0 - Double(utcOffsetMinutes)) / 1440.0
        let century = julianCentury(julianDay + localNoonDayFraction)

        let declination = sunDeclinationDegrees(century)
        let solarNoonMinutes = 720.0 - 4.0 * coordinate.longitude
            - equationOfTimeMinutes(century) + Double(utcOffsetMinutes)

        guard let hourAngle = sunriseHourAngleDegrees(latitude: coordinate.latitude,
                                                       declination: declination) else {
            return SolarEvents(sunriseMinute: nil,
                               solarNoonMinute: wrappedMinute(solarNoonMinutes),
                               sunsetMinute: nil)
        }
        return SolarEvents(sunriseMinute: wrappedMinute(solarNoonMinutes - 4.0 * hourAngle),
                           solarNoonMinute: wrappedMinute(solarNoonMinutes),
                           sunsetMinute: wrappedMinute(solarNoonMinutes + 4.0 * hourAngle))
    }

    /// Sun elevation in degrees above the horizon (negative when the sun is below it) at an
    /// explicit minute-of-day, calendar date, and UTC offset — the arbitrary-time counterpart to
    /// `events`, built from the same NOAA declination and equation-of-time terms. Location Mode
    /// samples this continuously through the day to drive brightness from the sun's real position,
    /// rather than only at the three named events.
    public static func elevationDegrees(atMinute minuteOfDay: Int, year: Int, month: Int, day: Int,
                                        coordinate: GeoCoordinate, utcOffsetMinutes: Int) -> Double {
        let dayFraction = (Double(minuteOfDay) - Double(utcOffsetMinutes)) / 1440.0
        let century = julianCentury(julianDay(year: year, month: month, day: day) + dayFraction)
        let declination = sunDeclinationDegrees(century)

        let trueSolarTimeMinutes = wrappedMinute(Double(minuteOfDay) + equationOfTimeMinutes(century)
            + 4.0 * coordinate.longitude - Double(utcOffsetMinutes))
        let hourAngleDegrees = Double(trueSolarTimeMinutes) / 4.0 - 180.0

        let latitudeRadians = radians(coordinate.latitude)
        let declinationRadians = radians(declination)
        let cosineZenith = sin(latitudeRadians) * sin(declinationRadians)
            + cos(latitudeRadians) * cos(declinationRadians) * cos(radians(hourAngleDegrees))
        let zenithDegrees = degrees(acos(min(1, max(-1, cosineZenith))))
        return 90.0 - zenithDegrees
    }

    /// Sun elevation for a `Date` in a `TimeZone`, honouring that zone's UTC offset on that day —
    /// the elevation counterpart to `events(on:in:coordinate:)`.
    public static func elevationDegrees(at date: Date, in timeZone: TimeZone,
                                        coordinate: GeoCoordinate) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minuteOfDay = (dayComponents.hour ?? 0) * 60 + (dayComponents.minute ?? 0)
        return elevationDegrees(atMinute: minuteOfDay, year: dayComponents.year ?? 2000,
                                month: dayComponents.month ?? 1, day: dayComponents.day ?? 1,
                                coordinate: coordinate,
                                utcOffsetMinutes: timeZone.secondsFromGMT(for: date) / 60)
    }

    // MARK: - NOAA equations (each in degrees unless the name says otherwise)

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var adjustedYear = year
        var adjustedMonth = month
        if adjustedMonth <= 2 {
            adjustedYear -= 1
            adjustedMonth += 12
        }
        let centuryGroup = adjustedYear / 100
        let gregorianOffset = 2 - centuryGroup + centuryGroup / 4
        return Double(Int(365.25 * Double(adjustedYear + 4716)))
            + Double(Int(30.6001 * Double(adjustedMonth + 1)))
            + Double(day) + Double(gregorianOffset) - 1524.5
    }

    private static func julianCentury(_ julianDay: Double) -> Double {
        (julianDay - 2451545.0) / 36525.0
    }

    private static func sunMeanLongitudeDegrees(_ century: Double) -> Double {
        normalizedDegrees(280.46646 + century * (36000.76983 + century * 0.0003032))
    }

    private static func sunMeanAnomalyDegrees(_ century: Double) -> Double {
        357.52911 + century * (35999.05029 - 0.0001537 * century)
    }

    private static func earthOrbitEccentricity(_ century: Double) -> Double {
        0.016708634 - century * (0.000042037 + 0.0000001267 * century)
    }

    private static func sunEquationOfCenterDegrees(_ century: Double) -> Double {
        let meanAnomaly = radians(sunMeanAnomalyDegrees(century))
        return sin(meanAnomaly) * (1.914602 - century * (0.004817 + 0.000014 * century))
            + sin(2 * meanAnomaly) * (0.019993 - 0.000101 * century)
            + sin(3 * meanAnomaly) * 0.000289
    }

    private static func sunApparentLongitudeDegrees(_ century: Double) -> Double {
        let trueLongitude = sunMeanLongitudeDegrees(century) + sunEquationOfCenterDegrees(century)
        return trueLongitude - 0.00569 - 0.00478 * sin(radians(moonAscendingNodeDegrees(century)))
    }

    private static func obliquityCorrectedDegrees(_ century: Double) -> Double {
        let arcSeconds = 21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))
        let meanObliquity = 23.0 + (26.0 + arcSeconds / 60.0) / 60.0
        return meanObliquity + 0.00256 * cos(radians(moonAscendingNodeDegrees(century)))
    }

    private static func moonAscendingNodeDegrees(_ century: Double) -> Double {
        125.04 - 1934.136 * century
    }

    private static func sunDeclinationDegrees(_ century: Double) -> Double {
        let obliquity = radians(obliquityCorrectedDegrees(century))
        let apparentLongitude = radians(sunApparentLongitudeDegrees(century))
        return degrees(asin(sin(obliquity) * sin(apparentLongitude)))
    }

    private static func equationOfTimeMinutes(_ century: Double) -> Double {
        let obliquityTangent = pow(tan(radians(obliquityCorrectedDegrees(century) / 2)), 2)
        let meanLongitude = radians(sunMeanLongitudeDegrees(century))
        let meanAnomaly = radians(sunMeanAnomalyDegrees(century))
        let eccentricity = earthOrbitEccentricity(century)
        let radians = obliquityTangent * sin(2 * meanLongitude)
            - 2 * eccentricity * sin(meanAnomaly)
            + 4 * eccentricity * obliquityTangent * sin(meanAnomaly) * cos(2 * meanLongitude)
            - 0.5 * obliquityTangent * obliquityTangent * sin(4 * meanLongitude)
            - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomaly)
        return 4 * degrees(radians)
    }

    /// The hour angle (degrees) between solar noon and sunrise, or nil at latitudes where the sun
    /// never crosses the sunrise zenith on this day (polar day/night).
    private static func sunriseHourAngleDegrees(latitude: Double, declination: Double) -> Double? {
        let latitudeRadians = radians(latitude)
        let declinationRadians = radians(declination)
        let cosineHourAngle = (cos(radians(sunriseZenithDegrees))
            - sin(latitudeRadians) * sin(declinationRadians))
            / (cos(latitudeRadians) * cos(declinationRadians))
        guard cosineHourAngle >= -1, cosineHourAngle <= 1 else { return nil }
        return degrees(acos(cosineHourAngle))
    }

    // MARK: - Small helpers

    private static func wrappedMinute(_ minutes: Double) -> Int {
        let rounded = Int(minutes.rounded())
        return ((rounded % 1440) + 1440) % 1440
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
