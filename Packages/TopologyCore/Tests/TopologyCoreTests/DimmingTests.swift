import XCTest
@testable import TopologyCore

final class DimmingTests: XCTestCase {
    // MARK: - Gamma method

    func testGammaNoDimIsIdentity() {
        XCTAssertEqual(DimmingComposer.split(method: .gamma, level: 1),
                       .init(gammaLevel: 1, overlayAlpha: 0))
    }

    func testGammaPassesLevelThrough() {
        XCTAssertEqual(DimmingComposer.split(method: .gamma, level: 0.5),
                       .init(gammaLevel: 0.5, overlayAlpha: 0))
    }

    func testGammaRespectsFloor() {
        let split = DimmingComposer.split(method: .gamma, level: 0)
        XCTAssertEqual(split.gammaLevel, DimmingComposer.gammaFloor)
        XCTAssertEqual(split.overlayAlpha, 0)
    }

    // MARK: - Overlay method

    func testOverlayLeavesGammaAlone() {
        let split = DimmingComposer.split(method: .overlay, level: 0.3)
        XCTAssertEqual(split.gammaLevel, 1)
        XCTAssertEqual(split.overlayAlpha, 0.7 * DimmingComposer.overlayAlphaCap, accuracy: 0.001)
    }

    func testOverlayMaxIsCappedBelowOpaque() {
        let split = DimmingComposer.split(method: .overlay, level: 0)
        XCTAssertEqual(split.overlayAlpha, DimmingComposer.overlayAlphaCap)
        XCTAssertLessThan(split.overlayAlpha, 1)
    }

    func testOverlayNoDimHasNoWindow() {
        XCTAssertEqual(DimmingComposer.split(method: .overlay, level: 1).overlayAlpha, 0)
    }

    // MARK: - Combined method

    func testCombinedNoDimIsIdentity() {
        XCTAssertEqual(DimmingComposer.split(method: .combined, level: 1),
                       .init(gammaLevel: 1, overlayAlpha: 0))
    }

    func testCombinedGammaLeadsOverlay() {
        // Inside the gamma share, only gamma moves.
        let early = DimmingComposer.split(method: .combined, level: 0.7)  // strength 0.3 < 0.55
        XCTAssertLessThan(early.gammaLevel, 1)
        XCTAssertEqual(early.overlayAlpha, 0)
    }

    func testCombinedOverlayJoinsAfterHandoff() {
        let late = DimmingComposer.split(method: .combined, level: 0.2)  // strength 0.8 > 0.55
        XCTAssertEqual(late.gammaLevel, DimmingComposer.gammaFloor)
        XCTAssertGreaterThan(late.overlayAlpha, 0)
    }

    func testCombinedMaxHitsBothLimits() {
        let split = DimmingComposer.split(method: .combined, level: 0)
        XCTAssertEqual(split.gammaLevel, DimmingComposer.gammaFloor)
        XCTAssertEqual(split.overlayAlpha, DimmingComposer.overlayAlphaCap)
    }

    func testCombinedGoesDarkerThanGammaAlone() {
        // Same slider position: combined must remove at least as much light as gamma-only, and at
        // the bottom of the range strictly more (the overlay stacks past the gamma floor).
        let gammaOnly = DimmingComposer.split(method: .gamma, level: 0)
        let combined = DimmingComposer.split(method: .combined, level: 0)
        let gammaLight = gammaOnly.gammaLevel * (1 - gammaOnly.overlayAlpha)
        let combinedLight = combined.gammaLevel * (1 - combined.overlayAlpha)
        XCTAssertLessThan(combinedLight, gammaLight)
    }

    // MARK: - Monotonicity + clamping

    func testDarknessIsMonotonicInEveryMethod() {
        for method in DimmingMethod.allCases {
            var previousLight: Float = .greatestFiniteMagnitude
            for step in stride(from: Float(1), through: 0, by: -0.05) {
                let split = DimmingComposer.split(method: method, level: step)
                let light = split.gammaLevel * (1 - split.overlayAlpha)
                XCTAssertLessThanOrEqual(light, previousLight + 0.0001,
                                         "\(method) got brighter as the slider went down at \(step)")
                previousLight = light
            }
        }
    }

    func testOutOfRangeLevelsClamp() {
        XCTAssertEqual(DimmingComposer.split(method: .gamma, level: 2),
                       DimmingComposer.split(method: .gamma, level: 1))
        XCTAssertEqual(DimmingComposer.split(method: .combined, level: -1),
                       DimmingComposer.split(method: .combined, level: 0))
    }
}
