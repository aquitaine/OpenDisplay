import DisplayDomain
import Foundation
import ProviderInterfaces

/// Faults that can be injected to drive the recovery/verification paths in tests
/// (PRD §15.2 provider-contract + fault-injection layers, T-006/T-008/T-013).
public struct SimulatedFaults: Sendable {
    /// If set, `disconnect` throws this failure (simulating a provider error).
    public var disconnectFailure: ProviderFailure?
    /// If `true`, `disconnect` returns without actually removing the display, so verification
    /// of postconditions must fail and trigger rollback (T-006 style).
    public var disconnectSilentlyNoOps: Bool
    /// If `true`, `recover` throws — simulating a failed rollback that degrades.
    public var recoverFails: Bool

    public init(
        disconnectFailure: ProviderFailure? = nil,
        disconnectSilentlyNoOps: Bool = false,
        recoverFails: Bool = false
    ) {
        self.disconnectFailure = disconnectFailure
        self.disconnectSilentlyNoOps = disconnectSilentlyNoOps
        self.recoverFails = recoverFails
    }

    public static let none = SimulatedFaults()
}

/// A deterministic, in-memory display topology that conforms to both `LifecycleProvider` and
/// `TopologyObserving`, so the platform-independent coordinator can be exercised end to end with
/// no macOS frameworks or real hardware.
public actor SimulatedDisplaySystem: LifecycleProvider, TopologyObserving {
    public nonisolated let providerID = "simulator.lifecycle.v1"
    public nonisolated let isExperimental = true

    private var observations: [DisplayObservation]
    private var managedOffline: [ManagedOfflineRecord]
    private var generation: TopologyGeneration
    private var faults: SimulatedFaults

    public init(
        observations: [DisplayObservation],
        managedOffline: [ManagedOfflineRecord] = [],
        generation: TopologyGeneration = .initial,
        faults: SimulatedFaults = .none
    ) {
        self.observations = observations
        self.managedOffline = managedOffline
        self.generation = generation
        self.faults = faults
    }

    public func setFaults(_ faults: SimulatedFaults) {
        self.faults = faults
    }

    // MARK: TopologyObserving

    public func currentSnapshot() -> TopologySnapshot {
        TopologySnapshot(generation: generation, observations: observations, managedOffline: managedOffline)
    }

    public func awaitStableGeneration(after generation: TopologyGeneration) -> TopologySnapshot {
        currentSnapshot()
    }

    // MARK: DisplayProvider

    public func probe(_ environment: ProviderEnvironment) -> ProviderProbe {
        ProviderProbe(
            providerID: providerID,
            status: environment.isAppleSilicon ? .supported : .unknown,
            risk: .experimental,
            reasons: environment.isAppleSilicon ? [] : [.architecture]
        )
    }

    // MARK: LifecycleProvider

    public func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        if let failure = faults.disconnectFailure { throw failure }
        if faults.disconnectSilentlyNoOps { return } // provider "succeeds" but state is unchanged

        guard let index = observations.firstIndex(where: { $0.recordID == target }) else {
            throw ProviderFailure.ambiguous(candidates: [])
        }
        bumpGeneration()
        observations[index].isActive = false
        observations[index].generation = generation
        managedOffline.append(
            ManagedOfflineRecord(displayID: target, actor: .ui, reason: "simulated", providerID: providerID)
        )
    }

    public func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        guard let index = observations.firstIndex(where: { $0.recordID == target }) else {
            throw ProviderFailure.ambiguous(candidates: [])
        }
        bumpGeneration()
        observations[index].isActive = true
        observations[index].generation = generation
        managedOffline.removeAll { $0.displayID == target }
    }

    public func recover(to checkpoint: Checkpoint) async throws {
        if faults.recoverFails { throw ProviderFailure.providerError(message: "simulated recover failure") }
        bumpGeneration()
        observations = checkpoint.observations.map {
            var copy = $0
            copy.generation = generation
            return copy
        }
        managedOffline = checkpoint.managedOffline
    }

    private func bumpGeneration() {
        generation = generation.next()
    }
}
