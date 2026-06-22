import XCTest
import DisplayDomain
import ProviderInterfaces
import SimulatorProvider
@testable import TopologyCore

/// In-memory checkpoint store for tests.
private actor TestCheckpointStore: CheckpointStoring {
    private var store: [CheckpointID: Checkpoint] = [:]
    private var latestID: CheckpointID?

    func writeAtomic(_ checkpoint: Checkpoint) async throws {
        store[checkpoint.id] = checkpoint
        latestID = checkpoint.id
    }
    func restore(_ id: CheckpointID) async throws -> Checkpoint? { store[id] }
    func latest() async -> Checkpoint? { latestID.flatMap { store[$0] } }
}

final class TopologyCoordinatorTests: XCTestCase {
    private func obs(_ id: String, active: Bool = true, main: Bool = false,
                     klass: DisplayClass = .external) -> DisplayObservation {
        DisplayObservation(recordID: DisplayRecordID(rawValue: id), isActive: active,
                           isMain: main, displayClass: klass, generation: .initial)
    }

    private func makeCoordinator(
        _ system: SimulatedDisplaySystem,
        confirm: @escaping ConfirmationHandler = { _, _ in true },
        recoveryHealthy: @escaping @Sendable () async -> Bool = { true }
    ) -> TopologyCoordinator {
        TopologyCoordinator(
            observer: system,
            lifecycleProvider: system,
            checkpoints: TestCheckpointStore(),
            recoveryServiceHealthy: recoveryHealthy,
            confirm: confirm
        )
    }

    // T-003: blocking the last safe display.
    func testBlocksRemovingLastSafeDisplay() async throws {
        let system = SimulatedDisplaySystem(observations: [obs("only", main: true, klass: .builtIn)])
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "only"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        XCTAssertEqual(result, .blocked([.wouldRemoveLastSafeDisplay]))
    }

    // T-001: first successful logical disconnect with a remaining safe surface.
    func testSuccessfulDisconnectCommits() async throws {
        let system = SimulatedDisplaySystem(observations: [
            obs("builtin", main: true, klass: .builtIn),
            obs("external")
        ])
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        guard case .committed(_, let verification) = result else {
            return XCTFail("expected committed, got \(result)")
        }
        XCTAssertEqual(verification, .verified)
        let finalState = await coordinator.currentState
        XCTAssertEqual(finalState, .committed)
        let snapshot = await system.currentSnapshot()
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "external"))?.isActive, false)
    }

    // T-006: a provider failure after checkpoint rolls back and recovers.
    func testProviderFailureRollsBackAndRecovers() async throws {
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("external")],
            faults: SimulatedFaults(disconnectFailure: .timeout)
        )
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        XCTAssertEqual(result, .rolledBack(resultTxID(result), recovered: true))
        let finalState = await coordinator.currentState
        XCTAssertEqual(finalState, .recovered)
    }

    // T-006 variant: provider "succeeds" but state is unchanged → verification fails → rollback.
    func testSilentNoOpFailsVerificationAndRollsBack() async throws {
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("external")],
            faults: SimulatedFaults(disconnectSilentlyNoOps: true)
        )
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        guard case .rolledBack(_, let recovered) = result else {
            return XCTFail("expected rolledBack, got \(result)")
        }
        XCTAssertTrue(recovered)
    }

    // A failed rollback degrades rather than silently succeeding.
    func testFailedRollbackDegrades() async throws {
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("external")],
            faults: SimulatedFaults(disconnectFailure: .providerError(message: "boom"), recoverFails: true)
        )
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        guard case .rolledBack(_, let recovered) = result else {
            return XCTFail("expected rolledBack, got \(result)")
        }
        XCTAssertFalse(recovered)
        let finalState = await coordinator.currentState
        XCTAssertEqual(finalState, .degraded)
    }

    // §9.4: if the provider drops an unrelated active display alongside the target, the coordinator
    // must roll back rather than commit — even though a third display remains a safe surface.
    func testRollsBackWhenProviderDropsUnrelatedDisplay() async throws {
        let system = SimulatedDisplaySystem(
            observations: [
                obs("builtin", main: true, klass: .builtIn),
                obs("external"),
                obs("third")
            ],
            faults: SimulatedFaults(alsoDisconnect: [DisplayRecordID(rawValue: "third")])
        )
        let coordinator = makeCoordinator(system)
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        guard case .rolledBack(_, let recovered) = result else {
            return XCTFail("expected rolledBack after losing an unrelated display, got \(result)")
        }
        XCTAssertTrue(recovered)
        // After rollback both the target and the unrelated display are restored.
        let snapshot = await system.currentSnapshot()
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "third"))?.isActive, true)
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "external"))?.isActive, true)
    }

    // Default coordinator (no confirmation handler supplied) must NOT silently approve a
    // `.needsConfirmation` disconnect — it cancels, leaving the display active.
    func testDefaultConfirmHandlerCancels() async throws {
        let system = SimulatedDisplaySystem(observations: [
            obs("builtin", main: true, klass: .builtIn), obs("external")
        ])
        // No `confirm:` argument → fail-safe default (deny).
        let coordinator = TopologyCoordinator(
            observer: system, lifecycleProvider: system, checkpoints: TestCheckpointStore()
        )
        let result = try await coordinator.disconnect(
            DisplayRecordID(rawValue: "external"),
            options: .init(actor: .ui, identityConfidence: 1.0, isFirstUseForRoute: true)
        )
        guard case .cancelled = result else { return XCTFail("expected cancelled, got \(result)") }
        let snapshot = await system.currentSnapshot()
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "external"))?.isActive, true)
    }

    // LIF-006: first-use confirmation that the user cancels.
    func testConfirmationCancelled() async throws {
        let system = SimulatedDisplaySystem(observations: [
            obs("builtin", main: true, klass: .builtIn), obs("external")
        ])
        let coordinator = makeCoordinator(system, confirm: { _, _ in false })
        let result = try await coordinator.disconnect(
            DisplayRecordID(rawValue: "external"),
            options: .init(actor: .ui, identityConfidence: 1.0, isFirstUseForRoute: true)
        )
        guard case .cancelled = result else { return XCTFail("expected cancelled, got \(result)") }
        // The display must remain active after a cancelled confirmation.
        let snapshot = await system.currentSnapshot()
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "external"))?.isActive, true)
    }

    // Recovery service unhealthy blocks the disconnect entirely.
    func testUnhealthyRecoveryServiceBlocks() async throws {
        let system = SimulatedDisplaySystem(observations: [
            obs("builtin", main: true, klass: .builtIn), obs("external")
        ])
        let coordinator = makeCoordinator(system, recoveryHealthy: { false })
        let result = try await coordinator.disconnect(DisplayRecordID(rawValue: "external"),
                                                       options: .init(actor: .ui, identityConfidence: 1.0))
        XCTAssertEqual(result, .blocked([.recoveryServiceUnhealthy]))
    }

    // LIF-009/010: Reconnect All returns per-target results.
    func testReconnectAllReturnsPerTargetResults() async throws {
        let offline = ManagedOfflineRecord(displayID: DisplayRecordID(rawValue: "external"),
                                            actor: .ui, reason: "test", providerID: "simulator.lifecycle.v1")
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("external", active: false)],
            managedOffline: [offline]
        )
        let coordinator = makeCoordinator(system)
        let results = await coordinator.reconnectAll()
        XCTAssertEqual(results[DisplayRecordID(rawValue: "external")], true)
        let snapshot = await system.currentSnapshot()
        XCTAssertEqual(snapshot.observation(for: DisplayRecordID(rawValue: "external"))?.isActive, true)
    }

    private func resultTxID(_ result: LifecycleResult) -> TransactionID {
        switch result {
        case .committed(let id, _), .noOp(let id), .cancelled(let id),
             .rolledBack(let id, _), .failed(let id, _):
            return id
        case .blocked:
            return TransactionID(rawValue: "n/a")
        }
    }
}
