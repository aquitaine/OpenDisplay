import XCTest
@testable import TopologyCore

final class ColorTemperatureTests: XCTestCase {
    func testNeutralIsExactIdentity() {
        XCTAssertEqual(ColorTemperatureCurve.gains(kelvin: 6500), .neutral)
    }

    func testWarmAttenuatesBlueKeepsRed() {
        let gains = ColorTemperatureCurve.gains(kelvin: 3000)
        XCTAssertEqual(gains.red, 1, accuracy: 0.0001)
        XCTAssertLessThan(gains.blue, gains.green)
        XCTAssertLessThan(gains.green, 1)
        XCTAssertGreaterThan(gains.blue, 0)  // warm, not yellow-only — blue never vanishes entirely
    }

    func testCoolAttenuatesRedKeepsBlue() {
        let gains = ColorTemperatureCurve.gains(kelvin: 9000)
        XCTAssertEqual(gains.blue, 1, accuracy: 0.0001)
        XCTAssertLessThan(gains.red, 1)
    }

    func testGainsNeverExceedOne() {
        for kelvin in stride(from: Float(2700), through: 9300, by: 100) {
            let gains = ColorTemperatureCurve.gains(kelvin: kelvin)
            XCTAssertLessThanOrEqual(gains.red, 1)
            XCTAssertLessThanOrEqual(gains.green, 1)
            XCTAssertLessThanOrEqual(gains.blue, 1)
            XCTAssertEqual(max(gains.red, gains.green, gains.blue), 1, accuracy: 0.0001,
                           "dominant channel must stay pinned at 1 (\(kelvin)K)")
        }
    }

    func testBlueIsMonotonicInKelvinOnTheWarmSide() {
        var previous: Float = -1
        for kelvin in stride(from: Float(2700), through: 6500, by: 100) {
            let blue = ColorTemperatureCurve.gains(kelvin: kelvin).blue
            XCTAssertGreaterThanOrEqual(blue, previous, "warmer should mean less blue (\(kelvin)K)")
            previous = blue
        }
    }

    func testClampsOutOfRangeKelvin() {
        XCTAssertEqual(ColorTemperatureCurve.gains(kelvin: 1000),
                       ColorTemperatureCurve.gains(kelvin: ColorTemperatureCurve.minKelvin))
        XCTAssertEqual(ColorTemperatureCurve.gains(kelvin: 20000),
                       ColorTemperatureCurve.gains(kelvin: ColorTemperatureCurve.maxKelvin))
    }
}
