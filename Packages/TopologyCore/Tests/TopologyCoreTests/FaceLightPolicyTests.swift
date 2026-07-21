import XCTest
@testable import TopologyCore

final class FaceLightPolicyTests: XCTestCase {
    private typealias Policy = FaceLightPolicy

    func testActivatingCapturesLivePriorStateAndMaxesBrightnessAndContrast() {
        let outcome = Policy.toggle(owedPriorState: nil, liveBrightness: 0.4, liveContrast: 0.5)
        XCTAssertTrue(outcome.isNowActive)
        XCTAssertEqual(outcome.brightnessWrite, 1.0)
        XCTAssertEqual(outcome.contrastWrite, 1.0)
        XCTAssertEqual(outcome.priorStateToPersist, Policy.PriorState(brightness: 0.4, contrast: 0.5))
    }

    func testActivatingWithNoDDCContrastSkipsTheContrastWrite() {
        // No-DDC (or DDC-without-contrast) displays get the overlay-only version: brightness still
        // maxes out, but there is no contrast channel to max or remember.
        let outcome = Policy.toggle(owedPriorState: nil, liveBrightness: 0.6, liveContrast: nil)
        XCTAssertEqual(outcome.brightnessWrite, 1.0)
        XCTAssertNil(outcome.contrastWrite)
        XCTAssertNil(outcome.priorStateToPersist?.contrast)
    }

    func testDeactivatingRestoresTheExactOwedPriorStateAndClearsTheLedger() {
        let owed = Policy.PriorState(brightness: 0.4, contrast: 0.5)
        let outcome = Policy.toggle(owedPriorState: owed, liveBrightness: 1.0, liveContrast: 1.0)
        XCTAssertFalse(outcome.isNowActive)
        XCTAssertEqual(outcome.brightnessWrite, 0.4)
        XCTAssertEqual(outcome.contrastWrite, 0.5)
        XCTAssertNil(outcome.priorStateToPersist)
    }

    func testDeactivatingWithNoOwedContrastRestoresBrightnessOnly() {
        let owed = Policy.PriorState(brightness: 0.7, contrast: nil)
        let outcome = Policy.toggle(owedPriorState: owed, liveBrightness: 1.0, liveContrast: nil)
        XCTAssertEqual(outcome.brightnessWrite, 0.7)
        XCTAssertNil(outcome.contrastWrite)
    }

    func testOverlayKelvinIsTheColorTemperatureCurvesWarmestStop() {
        XCTAssertEqual(Policy.overlayKelvin, ColorTemperatureCurve.minKelvin)
    }

    func testOverlayAlphaIsAStrongButTranslucentWash() {
        // Opaque (1.0) would blind the panel underneath — including the video call itself on a
        // single-monitor setup — and too faint (below 0.4) wouldn't read as a fill light.
        XCTAssertGreaterThanOrEqual(Policy.overlayAlpha, 0.4)
        XCTAssertLessThanOrEqual(Policy.overlayAlpha, 0.6)
        XCTAssertLessThan(Policy.overlayAlpha, 1.0)
    }

    func testPriorStateRoundTripsThroughJSON() throws {
        let priorState = Policy.PriorState(brightness: 0.42, contrast: 0.73)
        let encoded = try JSONEncoder().encode(priorState)
        let decoded = try JSONDecoder().decode(Policy.PriorState.self, from: encoded)
        XCTAssertEqual(decoded, priorState)
    }
}
