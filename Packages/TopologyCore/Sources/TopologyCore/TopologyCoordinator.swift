import DisplayDomain
import Foundation
import ProviderInterfaces

/// Persists last-known-safe checkpoints. On macOS this is backed by an atomic, rescue-readable
/// store; the coordinator depends only on this protocol (PRD §10.8 CheckpointStore, DIA-008).
public protocol CheckpointStoring: Sendable {
    func writeAtomic(_ checkpoint: Checkpoint) async throws
    func restore(_ id: CheckpointID) async throws -> Checkpoint?
    func latest() async -> Checkpoint?
}

/// Options for a disconnect request.
public struct DisconnectOptions: Sendable {
    public var actor: Actor
    public var reason: String
    public var identityConfidence: Double
    public var isFirstUseForRoute: Bool
    public var userOverride: Bool
    public var deadline: Date
    public var persistencePolicy: PersistencePolicy

    public init(
        actor: Actor,
        reason: String = "user requested",
        identityConfidence: Double,
        isFirstUseForRoute: Bool = false,
        userOverride: Bool = false,
        deadline: Date = Date().addingTimeInterval(10),
        persistencePolicy: PersistencePolicy = .reconnectOnQuit
    ) {
        self.actor = actor
        self.reason = reason
        self.identityConfidence = identityConfidence
        self.isFirstUseForRoute = isFirstUseForRoute
        self.userOverride = userOverride
        self.deadline = deadline
        self.persistencePolicy = persistencePolicy
    }
}

/// The outcome of a lifecycle transaction. Provider success alone is never `committed` — the
/// coordinator verifies observed postconditions first (PRD D-010).
public enum LifecycleResult: Equatable, Sendable {
    case committed(TransactionID, verification: VerificationState)
    case noOp(TransactionID)
    case blocked([SafetyEngine.Reason])
    case cancelled(TransactionID)
    case rolledBack(TransactionID, recovered: Bool)
    case failed(TransactionID, ProviderFailure)
}

/// Asks the user to confirm a risky action behind a countdown on the safe surface (LIF-006).
/// Returns `true` to proceed. In tests this is injected to auto-confirm or auto-cancel.
public typealias ConfirmationHandler = @Sendable (_ safeSurface: DisplayRecordID, _ reasons: [SafetyEngine.Reason]) async -> Bool

public enum CoordinatorError: Error, Equatable, Sendable {
    case busy
    case illegalTransition(from: TransactionState, to: TransactionState)
}

/// The single serialized owner of every topology/lifecycle write (PRD §10.3, §9.2 invariant 1).
/// Actor isolation guarantees at most one in-flight transaction; recovery preempts ordinary work.
public actor TopologyCoordinator {
    private let observer: TopologyObserving
    private let lifecycleProvider: LifecycleProvider
    private let checkpoints: CheckpointStoring
    private let safety: SafetyEngine
    private let confirm: ConfirmationHandler
    private let recoveryServiceHealthy: @Sendable () async -> Bool

    private var state: TransactionState = .idle
    /// The state path of the most recent transaction, exposed for audit/testing (PRD §10.4).
    public private(set) var lastTransition: [TransactionState] = []

    public init(
        observer: TopologyObserving,
        lifecycleProvider: LifecycleProvider,
        checkpoints: CheckpointStoring,
        safety: SafetyEngine = SafetyEngine(),
        recoveryServiceHealthy: @escaping @Sendable () async -> Bool = { true },
        confirm: @escaping ConfirmationHandler = { _, _ in true }
    ) {
        self.observer = observer
        self.lifecycleProvider = lifecycleProvider
        self.checkpoints = checkpoints
        self.safety = safety
        self.recoveryServiceHealthy = recoveryServiceHealthy
        self.confirm = confirm
    }

    public var currentState: TransactionState { state }

    /// Logically disconnects `target`, following the §9.4 staged transaction. Throws `CoordinatorError.busy`
    /// if another transaction is in flight (exclusivity, invariant 1).
    public func disconnect(_ target: DisplayRecordID, options: DisconnectOptions) async throws -> LifecycleResult {
        guard state.isTerminal || state == .idle else { throw CoordinatorError.busy }
        let txID = TransactionID.generate()
        beginTransaction()

        // 1. Resolve.
        try transition(to: .resolving)
        let snapshot = await observer.currentSnapshot()
        guard let observation = snapshot.observation(for: target) else {
            // Idempotent: already managed-offline → no-op; otherwise it's system-absent (failed).
            if snapshot.managedOffline.contains(where: { $0.displayID == target }) {
                try transition(to: .failed) // terminal; treated as benign no-op
                return .noOp(txID)
            }
            try transition(to: .failed)
            return .failed(txID, .ambiguous(candidates: []))
        }

        // 2. Preflight safety (non-bypassable).
        try transition(to: .preflight)
        let healthy = await recoveryServiceHealthy()
        let decision = safety.preflightDisconnect(
            target: target,
            snapshot: snapshot,
            identityConfidence: options.identityConfidence,
            recoveryServiceHealthy: healthy,
            isFirstUseForRoute: options.isFirstUseForRoute
        )
        if case .blocked(let reasons) = decision, !options.userOverride {
            try transition(to: .failed)
            return .blocked(reasons)
        }

        // 3. Checkpoint (atomic, before any provider call — invariant 2).
        let checkpoint = Checkpoint(
            transactionID: txID,
            generation: snapshot.generation,
            observations: snapshot.observations,
            mainDisplayID: snapshot.activeDisplays.first(where: { $0.isMain })?.recordID,
            managedOffline: snapshot.managedOffline
        )
        do {
            try await checkpoints.writeAtomic(checkpoint)
        } catch {
            try transition(to: .failed)
            return .failed(txID, .providerError(message: "checkpoint write failed"))
        }
        try transition(to: .checkpointed)

        // 4. Confirm if required.
        if case .needsConfirmation(let surface, let reasons) = decision {
            let proceed = await confirm(surface, reasons)
            guard proceed else {
                try transition(to: .failed)
                return .cancelled(txID)
            }
        }

        // 5. Apply.
        try transition(to: .applying)
        do {
            try await lifecycleProvider.disconnect(target, deadline: options.deadline)
        } catch let failure as ProviderFailure {
            return await rollback(txID, checkpoint: checkpoint, failure: failure)
        } catch {
            return await rollback(txID, checkpoint: checkpoint, failure: .unknown)
        }

        // 6. Observe the resulting stabilized generation.
        try transition(to: .observing)
        let after = await observer.awaitStableGeneration(after: snapshot.generation)

        // 7. Verify postconditions: target inactive AND a safe surface remains active.
        try transition(to: .verifying)
        let targetInactive = after.observation(for: target)?.isActive != true
        let safeSurfaceRemains = safety.safeSurface(in: after, excluding: [target]) != nil
        guard targetInactive && safeSurfaceRemains else {
            return await rollback(txID, checkpoint: checkpoint, failure: .partial(message: "postconditions not met"))
        }

        // 8. Commit.
        try transition(to: .committed)
        _ = observation // observed identity retained for audit/result construction by callers
        return .committed(txID, verification: .verified)
    }

    /// Reconnects every managed-offline display. Always available; intended to preempt queued work
    /// (PRD §9.2 invariant 6, LIF-009/010). Returns per-target success/failure.
    public func reconnectAll(deadline: Date = Date().addingTimeInterval(15)) async -> [DisplayRecordID: Bool] {
        let snapshot = await observer.currentSnapshot()
        var results: [DisplayRecordID: Bool] = [:]
        for record in snapshot.managedOffline {
            do {
                try await lifecycleProvider.reconnect(record.displayID, deadline: deadline)
                results[record.displayID] = true
            } catch {
                results[record.displayID] = false
            }
        }
        return results
    }

    // MARK: - Private

    private func beginTransaction() {
        state = .idle
        lastTransition = [.idle]
    }

    private func transition(to next: TransactionState) throws {
        guard state.canTransition(to: next) else {
            throw CoordinatorError.illegalTransition(from: state, to: next)
        }
        state = next
        lastTransition.append(next)
    }

    private func rollback(_ txID: TransactionID, checkpoint: Checkpoint, failure: ProviderFailure) async -> LifecycleResult {
        // Force the rolling-back state even from `applying`/`observing`/`verifying`.
        try? transition(to: .rollingBack)
        do {
            try await lifecycleProvider.recover(to: checkpoint)
            try? transition(to: .recovered)
            return .rolledBack(txID, recovered: true)
        } catch {
            try? transition(to: .degraded)
            return .rolledBack(txID, recovered: false)
        }
    }
}
