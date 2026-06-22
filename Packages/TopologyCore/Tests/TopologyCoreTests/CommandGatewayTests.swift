import XCTest
import AutomationSchema
import DisplayDomain
import ProviderInterfaces
import SimulatorProvider
@testable import TopologyCore

final class CommandGatewayTests: XCTestCase {
    private func obs(_ id: String, active: Bool = true, main: Bool = false,
                     klass: DisplayClass = .external) -> DisplayObservation {
        DisplayObservation(recordID: .init(rawValue: id), isActive: active, isMain: main,
                           displayClass: klass, generation: .initial)
    }

    private func offline(_ id: String) -> ManagedOfflineRecord {
        ManagedOfflineRecord(displayID: .init(rawValue: id), actor: .ui, reason: "test",
                             providerID: "simulator.lifecycle.v1")
    }

    func testReconnectAllReenablesManagedOffline() async {
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("ext", active: false)],
            managedOffline: [offline("ext")]
        )
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.reconnectAll(actor: .cli)
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.actor, .cli)
        XCTAssertEqual(envelope.targets.map(\.displayId), ["ext"])
        XCTAssertEqual(envelope.targets.first?.operations.first?.verification, .verified)
        XCTAssertEqual(envelope.schemaVersion, ResultEnvelope.currentSchemaVersion)
    }

    func testReconnectAllNoOpWhenNothingOffline() async {
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn)])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.reconnectAll()
        XCTAssertEqual(envelope.status, .noOp)
        XCTAssertTrue(envelope.targets.isEmpty)
    }

    func testDisconnectCommitsWhenSafeSurfaceRemains() async {
        // Default confirm handler declines, so reaching .committed proves preflight returned
        // .allowed (no confirmation needed) for a non-main target with the built-in as safe surface.
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.disconnect(.init(rawValue: "ext"),
                                                options: DisconnectOptions(actor: .cli, identityConfidence: 1.0))
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.targets.first?.operations.first?.verification, .verified)
    }

    func testDisconnectBlockedWhenRemovingLastSafeDisplay() async {
        let system = SimulatedDisplaySystem(observations: [obs("only", main: true, klass: .builtIn)])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.disconnect(.init(rawValue: "only"),
                                                options: DisconnectOptions(actor: .cli, identityConfidence: 1.0))
        XCTAssertEqual(envelope.status, .failed)
        XCTAssertTrue(envelope.errors.contains { $0.code == "blocked" })
    }

    func testPreflightAllowedAndBlocked() async {
        let pair = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let gateway = CommandGateway(observer: pair, lifecycleProvider: pair, checkpoints: InMemoryCheckpointStore())
        let allowed = await gateway.preflightDisconnect(.init(rawValue: "ext"), identityConfidence: 1.0)
        XCTAssertEqual(allowed.decision, .allowed)
        XCTAssertEqual(allowed.safeSurface, DisplayRecordID(rawValue: "builtin"))

        let single = SimulatedDisplaySystem(observations: [obs("only", main: true, klass: .builtIn)])
        let gateway2 = CommandGateway(observer: single, lifecycleProvider: single, checkpoints: InMemoryCheckpointStore())
        let blocked = await gateway2.preflightDisconnect(.init(rawValue: "only"), identityConfidence: 1.0)
        XCTAssertEqual(blocked.decision, .blocked)
        XCTAssertNil(blocked.safeSurface)
    }

    func testEnvelopeMappingCoversEveryResult() {
        let target = DisplayRecordID(rawValue: "d")
        let tx = TransactionID(rawValue: "txn_1")
        func status(_ result: LifecycleResult) -> ResultEnvelope.Status {
            CommandGateway.envelope(for: result, target: target, actor: .cli, generation: 5).status
        }
        XCTAssertEqual(status(.committed(tx, verification: .verified)), .committed)
        XCTAssertEqual(status(.noOp(tx)), .noOp)
        XCTAssertEqual(status(.cancelled(tx)), .noOp)
        XCTAssertEqual(status(.rolledBack(tx, recovered: true)), .rolledBack)
        XCTAssertEqual(status(.failed(tx, .denied)), .failed)
        XCTAssertEqual(status(.blocked([.noSafeSurface])), .failed)
    }
}
