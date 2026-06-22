import XCTest
import DisplayDomain
@testable import TopologyCore

final class SafetyEngineTests: XCTestCase {
    private let engine = SafetyEngine()

    private func obs(_ id: String, active: Bool = true, main: Bool = false,
                     klass: DisplayClass = .external, overlay: PresentationOverlay = .visible,
                     mirrorOf: DisplayRecordID? = nil) -> DisplayObservation {
        DisplayObservation(recordID: DisplayRecordID(rawValue: id), isActive: active, overlay: overlay,
                           isMain: main, mirrorSourceID: mirrorOf, displayClass: klass, generation: .initial)
    }

    func testSafeSurfacePrefersBuiltIn() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("external", main: true, klass: .external),
            obs("builtin", klass: .builtIn)
        ])
        let surface = engine.safeSurface(in: snapshot, excluding: [])
        XCTAssertEqual(surface, DisplayRecordID(rawValue: "builtin"))
    }

    func testSafeSurfaceExcludesTargetsAndMirrorsAndBlackedOut() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("target", klass: .external),
            obs("mirror", mirrorOf: DisplayRecordID(rawValue: "target")),
            obs("blacked", overlay: .blackedOut),
            obs("good", klass: .external)
        ])
        let surface = engine.safeSurface(in: snapshot, excluding: [DisplayRecordID(rawValue: "target")])
        XCTAssertEqual(surface, DisplayRecordID(rawValue: "good"))
    }

    func testDisconnectingCurrentMainNeedsConfirmation() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("builtin", main: true, klass: .builtIn),
            obs("external")
        ])
        let decision = engine.preflightDisconnect(
            target: DisplayRecordID(rawValue: "builtin"),
            snapshot: snapshot,
            identityConfidence: 1.0,
            recoveryServiceHealthy: true,
            isFirstUseForRoute: false
        )
        guard case .needsConfirmation(_, let reasons) = decision else {
            return XCTFail("expected needsConfirmation, got \(decision)")
        }
        XCTAssertTrue(reasons.contains(.targetIsCurrentMain))
    }

    func testLowConfidenceNeedsConfirmation() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("builtin", main: true, klass: .builtIn), obs("external")
        ])
        let decision = engine.preflightDisconnect(
            target: DisplayRecordID(rawValue: "external"),
            snapshot: snapshot,
            identityConfidence: 0.4,
            recoveryServiceHealthy: true,
            isFirstUseForRoute: false
        )
        guard case .needsConfirmation(_, let reasons) = decision else {
            return XCTFail("expected needsConfirmation, got \(decision)")
        }
        XCTAssertTrue(reasons.contains(.identityBelowThreshold))
    }

    func testAllowedWhenSafeAndConfident() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("builtin", main: true, klass: .builtIn), obs("external")
        ])
        let decision = engine.preflightDisconnect(
            target: DisplayRecordID(rawValue: "external"),
            snapshot: snapshot,
            identityConfidence: 1.0,
            recoveryServiceHealthy: true,
            isFirstUseForRoute: false
        )
        guard case .allowed(let surface) = decision else {
            return XCTFail("expected allowed, got \(decision)")
        }
        XCTAssertEqual(surface, DisplayRecordID(rawValue: "builtin"))
    }
}
