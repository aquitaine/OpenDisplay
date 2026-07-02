import XCTest
import DisplayDomain
@testable import TopologyCore

final class DisplayConfigDrifterTests: XCTestCase {
    private func obs(
        _ id: String, active: Bool = true, main: Bool = false,
        origin: DisplayOrigin = .init(x: 0, y: 0), mode: DisplayMode? = nil,
        rotation: Rotation = .degrees0, mirror: String? = nil
    ) -> DisplayObservation {
        DisplayObservation(
            recordID: .init(rawValue: id), isActive: active, origin: origin, mode: mode,
            rotation: rotation, isMain: main, mirrorSourceID: mirror.map { .init(rawValue: $0) },
            displayClass: .external, generation: .initial
        )
    }
    private func snap(_ obs: [DisplayObservation]) -> TopologySnapshot {
        TopologySnapshot(generation: .initial, observations: obs)
    }
    private func mode(_ w: Int, _ h: Int) -> DisplayMode {
        DisplayMode(pixelWidth: w, pixelHeight: h, pointWidth: w, pointHeight: h, refreshHz: 60, isHiDPI: false)
    }

    func testNoDriftForIdenticalSnapshots() {
        let s = snap([obs("A", main: true, origin: .init(x: 0, y: 0)), obs("B", origin: .init(x: 1920, y: 0))])
        XCTAssertFalse(DisplayConfigDrifter.detectDrift(protected: s, current: s).hasDrifted)
        XCTAssertTrue(DisplayConfigDrifter.detectDrift(protected: s, current: s).changes.isEmpty)
    }

    func testOriginMoved() {
        let p = snap([obs("A", main: true), obs("B", origin: .init(x: 1920, y: 0))])
        let c = snap([obs("A", main: true), obs("B", origin: .init(x: -1920, y: 0))])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.originMoved(.init(rawValue: "B"))])
    }

    func testModeChanged() {
        let p = snap([obs("A", main: true, mode: mode(1920, 1080))])
        let c = snap([obs("A", main: true, mode: mode(2560, 1440))])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.modeChanged(.init(rawValue: "A"))])
    }

    func testRotationChanged() {
        let p = snap([obs("A", main: true, rotation: .degrees0)])
        let c = snap([obs("A", main: true, rotation: .degrees90)])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.rotationChanged(.init(rawValue: "A"))])
    }

    func testMirrorChanged() {
        let p = snap([obs("A", main: true), obs("B")])
        let c = snap([obs("A", main: true), obs("B", mirror: "A")])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.mirrorChanged(.init(rawValue: "B"))])
    }

    func testActiveChanged() {
        let p = snap([obs("A", main: true), obs("B", active: true)])
        let c = snap([obs("A", main: true), obs("B", active: false)])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.activeChanged(.init(rawValue: "B"))])
    }

    func testMainChanged() {
        let p = snap([obs("A", main: true), obs("B", main: false)])
        let c = snap([obs("A", main: false), obs("B", main: true)])
        XCTAssertEqual(
            DisplayConfigDrifter.detectDrift(protected: p, current: c).changes,
            [.mainChanged(from: .init(rawValue: "A"), to: .init(rawValue: "B"))]
        )
    }

    func testDisconnected() {
        let p = snap([obs("A", main: true), obs("B")])
        let c = snap([obs("A", main: true)])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.disconnected(.init(rawValue: "B"))])
    }

    func testAppeared() {
        let p = snap([obs("A", main: true)])
        let c = snap([obs("A", main: true), obs("B")])
        XCTAssertEqual(DisplayConfigDrifter.detectDrift(protected: p, current: c).changes, [.appeared(.init(rawValue: "B"))])
    }

    func testMultipleChangesAreOrderedDeterministically() {
        let p = snap([obs("A", main: true, mode: mode(1920, 1080)), obs("B", origin: .init(x: 1920, y: 0))])
        let c = snap([obs("A", main: false, mode: mode(2560, 1440)), obs("B", main: true, origin: .init(x: 0, y: 0))])
        let changes = DisplayConfigDrifter.detectDrift(protected: p, current: c).changes
        // A: mode changed; B: origin moved; then main changed A→B. Per-display first (sorted), main last.
        XCTAssertEqual(changes, [
            .modeChanged(.init(rawValue: "A")),
            .originMoved(.init(rawValue: "B")),
            .mainChanged(from: .init(rawValue: "A"), to: .init(rawValue: "B")),
        ])
    }

    func testProtectedConfigAndAnalysisCodableRoundTrip() throws {
        let cfg = ProtectedConfig(snapshot: snap([obs("A", main: true)]), capturedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try JSONDecoder().decode(ProtectedConfig.self, from: JSONEncoder().encode(cfg)), cfg)
        let analysis = DisplayConfigDrifter.DriftAnalysis(changes: [.originMoved(.init(rawValue: "X")), .mainChanged(from: nil, to: .init(rawValue: "Y"))])
        XCTAssertEqual(try JSONDecoder().decode(DisplayConfigDrifter.DriftAnalysis.self, from: JSONEncoder().encode(analysis)), analysis)
    }
}
