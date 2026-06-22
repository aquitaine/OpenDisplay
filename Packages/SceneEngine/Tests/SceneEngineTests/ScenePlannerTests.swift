import XCTest
import DisplayDomain
@testable import SceneEngine

final class ScenePlannerTests: XCTestCase {
    private let center = DisplayRecordID(rawValue: "disp_center")
    private let left = DisplayRecordID(rawValue: "disp_left")
    private let builtin = DisplayRecordID(rawValue: "disp_builtin")

    private func observation(_ id: DisplayRecordID, active: Bool, main: Bool = false, origin: DisplayOrigin = .zero) -> DisplayObservation {
        DisplayObservation(recordID: id, isActive: active, origin: origin, isMain: main, generation: .initial)
    }

    func testFullySatisfiedSceneHasNoWork() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            observation(center, active: true, main: true),
            observation(left, active: true, origin: DisplayOrigin(x: -1920, y: 0))
        ])
        let scene = Scene(id: "studio", name: "Studio", members: [
            .init(selector: "alias:Center", required: true, desired: DesiredState(connected: true, main: true)),
            .init(selector: "alias:Left", required: true,
                  desired: DesiredState(connected: true, position: DisplayOrigin(x: -1920, y: 0)))
        ])
        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot,
                                       resolution: ["alias:Center": center, "alias:Left": left])
        XCTAssertFalse(plan.hasWork, "An already-satisfied scene must produce no actionable operations (TOP-013).")
        XCTAssertTrue(plan.operations.allSatisfy { $0.status == .alreadySatisfied })
    }

    func testDisconnectIsOrderedLastAndReconnectFirst() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            observation(center, active: true, main: true),
            observation(builtin, active: true),
            observation(left, active: false)
        ])
        let scene = Scene(id: "work", name: "Work", members: [
            .init(selector: "builtin", required: false, desired: DesiredState(connected: false)),
            .init(selector: "alias:Left", required: true, desired: DesiredState(connected: true)),
            .init(selector: "alias:Center", required: true, desired: DesiredState(main: true))
        ])
        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot,
                                       resolution: ["builtin": builtin, "alias:Left": left, "alias:Center": center])
        let kinds = plan.operations.map(\.kind)
        let reconnectIndex = kinds.firstIndex(of: .reconnect)
        let disconnectIndex = kinds.firstIndex(of: .disconnect)
        XCTAssertNotNil(reconnectIndex)
        XCTAssertNotNil(disconnectIndex)
        XCTAssertLessThan(reconnectIndex!, disconnectIndex!,
                          "Reconnect must come before disconnect so a safe surface exists first (§10.7).")
    }

    func testMissingRequiredMemberBlocksPlan() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [observation(center, active: true)])
        let scene = Scene(id: "x", name: "X", members: [
            .init(selector: "alias:Missing", required: true, desired: DesiredState(connected: true))
        ])
        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot, resolution: [:])
        XCTAssertTrue(plan.isBlocked)
        XCTAssertEqual(plan.missingRequired, ["alias:Missing"])
    }

    func testMissingOptionalMemberDoesNotBlock() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [observation(center, active: true)])
        let scene = Scene(id: "x", name: "X", members: [
            .init(selector: "alias:Center", required: true, desired: DesiredState(main: true)),
            .init(selector: "builtin", required: false, desired: DesiredState(connected: false))
        ])
        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot, resolution: ["alias:Center": center])
        XCTAssertFalse(plan.isBlocked)
        XCTAssertEqual(plan.missingOptional, ["builtin"])
    }

    func testPlanIsDeterministicRegardlessOfMemberOrder() {
        let snapshot = TopologySnapshot(generation: .initial, observations: [
            observation(center, active: true), observation(left, active: false)
        ])
        let membersA: [Scene.Member] = [
            .init(selector: "alias:Center", required: true, desired: DesiredState(main: true)),
            .init(selector: "alias:Left", required: true, desired: DesiredState(connected: true))
        ]
        let resolution = ["alias:Center": center, "alias:Left": left]
        let planA = ScenePlanner().plan(scene: Scene(id: "s", name: "S", members: membersA),
                                        snapshot: snapshot, resolution: resolution)
        let planB = ScenePlanner().plan(scene: Scene(id: "s", name: "S", members: membersA.reversed()),
                                        snapshot: snapshot, resolution: resolution)
        XCTAssertEqual(planA.operations, planB.operations)
    }
}
