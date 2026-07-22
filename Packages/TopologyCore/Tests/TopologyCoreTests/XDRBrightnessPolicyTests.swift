import XCTest
@testable import TopologyCore

final class XDRBrightnessPolicyTests: XCTestCase {
    func testFractionZeroIsNoBoost() {
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 0, headroom: 8.6), 1.0)
    }

    func testFullFractionIsCappedAtMaxBoost() {
        // The panel advertises far more digital headroom (16×) than its backlight can deliver;
        // the boost stops at the real 1600/500 nit ratio.
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 1, headroom: 16),
                       XDRBrightnessPolicy.maxBoost)
    }

    func testFullFractionFollowsHeadroomBelowTheCap() {
        // Mid-ramp (backlight still rising) the usable ceiling is the live headroom.
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 1, headroom: 2), 2.0)
    }

    func testHeadroomOfOneMeansNoBoostAtAnyFraction() {
        // EDR not (yet) engaged — there is no attenuation to map back up.
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 0.5, headroom: 1), 1.0)
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 1, headroom: 1), 1.0)
    }

    func testSubUnityHeadroomNeverDimsBelowOne() {
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 1, headroom: 0.5), 1.0)
    }

    func testFractionIsClamped() {
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: -0.5, headroom: 4), 1.0)
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 1.5, headroom: 4),
                       XDRBrightnessPolicy.boost(forFraction: 1, headroom: 4))
    }

    func testMidFractionInterpolatesLinearly() {
        XCTAssertEqual(XDRBrightnessPolicy.boost(forFraction: 0.5, headroom: 3), 2.0, accuracy: 0.0001)
    }

    func testIsEngagedThreshold() {
        XCTAssertFalse(XDRBrightnessPolicy.isEngaged(boost: 1.0))
        XCTAssertFalse(XDRBrightnessPolicy.isEngaged(boost: 1.001))
        XCTAssertTrue(XDRBrightnessPolicy.isEngaged(boost: 1.01))
    }
}
