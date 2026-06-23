import XCTest
import DisplayDomain
@testable import SceneEngine

final class SceneRecorderTests: XCTestCase {
    private func obs(_ id: String, active: Bool = true, main: Bool = false, x: Int = 0, y: Int = 0) -> DisplayObservation {
        DisplayObservation(recordID: .init(rawValue: id), isActive: active,
                           origin: .init(x: x, y: y), isMain: main, generation: .initial)
    }

    func testCaptureThenPlanIsIdempotent() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            obs("cg:A", main: true), obs("cg:B", x: 1920)
        ])
        let scene = SceneRecorder.capture(from: snapshot, name: "Desk", id: "scene_1")
        let resolution = SceneRecorder.resolution(for: scene, in: snapshot)
        XCTAssertEqual(resolution.count, 2)

        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot, resolution: resolution)
        XCTAssertFalse(plan.hasWork)
        XCTAssertTrue(plan.operations.allSatisfy { $0.status == .alreadySatisfied })
        XCTAssertTrue(plan.missingRequired.isEmpty)
    }

    func testPlanDetectsAMovedDisplay() {
        let atCapture = TopologySnapshot(generation: .initial, observations: [
            obs("cg:A", main: true), obs("cg:B", x: 1920)
        ])
        let scene = SceneRecorder.capture(from: atCapture, name: "Desk", id: "scene_1")

        // "cg:B" has since moved to a different origin.
        let now = TopologySnapshot(generation: .initial, observations: [
            obs("cg:A", main: true), obs("cg:B", x: 800)
        ])
        let plan = ScenePlanner().plan(scene: scene, snapshot: now,
                                       resolution: SceneRecorder.resolution(for: scene, in: now))
        XCTAssertTrue(plan.hasWork)
        XCTAssertTrue(plan.operations.contains { $0.kind == .setPosition && $0.status == .willApply })
    }

    func testAbsentDisplayIsMissingOptionalNotBlocking() {
        let atCapture = TopologySnapshot(generation: .initial, observations: [
            obs("cg:A", main: true), obs("cg:B", x: 1920)
        ])
        let scene = SceneRecorder.capture(from: atCapture, name: "Desk", id: "scene_1")

        // "cg:B" is gone now → optional miss, not a block.
        let now = TopologySnapshot(generation: .initial, observations: [obs("cg:A", main: true)])
        let plan = ScenePlanner().plan(scene: scene, snapshot: now,
                                       resolution: SceneRecorder.resolution(for: scene, in: now))
        XCTAssertFalse(plan.isBlocked)
        XCTAssertEqual(plan.missingOptional, ["id:cg:B"])
    }
}
