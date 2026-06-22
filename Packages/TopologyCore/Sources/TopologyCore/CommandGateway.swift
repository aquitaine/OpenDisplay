import AutomationSchema
import DisplayDomain
import Foundation
import ProviderInterfaces

/// The single entry point every external command surface (UI, CLI, App Intents, local HTTP) goes
/// through (PRD §10 CommandGateway / AutomationGateway). It owns one `TopologyCoordinator`, so all
/// commands share the same serialized, safety-checked, audited path, and it translates the
/// coordinator's internal `LifecycleResult` into the stable, versioned `ResultEnvelope` that every
/// automation surface returns — keeping that mapping in one tested place instead of duplicated per
/// surface. Platform-independent: callers inject the concrete observer/lifecycle providers.
public actor CommandGateway {
    private let observer: TopologyObserving
    private let lifecycle: LifecycleProvider
    private let coordinator: TopologyCoordinator
    private let safety: SafetyEngine

    public init(
        observer: TopologyObserving,
        lifecycleProvider: LifecycleProvider,
        checkpoints: CheckpointStoring,
        safety: SafetyEngine = SafetyEngine(),
        recoveryServiceHealthy: @escaping @Sendable () async -> Bool = { true },
        confirm: @escaping ConfirmationHandler = { _, _ in false }
    ) {
        self.observer = observer
        self.lifecycle = lifecycleProvider
        self.safety = safety
        self.coordinator = TopologyCoordinator(
            observer: observer,
            lifecycleProvider: lifecycleProvider,
            checkpoints: checkpoints,
            safety: safety,
            recoveryServiceHealthy: recoveryServiceHealthy,
            confirm: confirm
        )
    }

    // MARK: - Commands

    /// Reconnects every managed-offline display and returns a per-target envelope.
    public func reconnectAll(actor: Actor = .ui) async -> ResultEnvelope {
        let results = await coordinator.reconnectAll()
        let snapshot = await observer.currentSnapshot()
        let targets = results
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { id, ok in
                ResultEnvelope.TargetResult(
                    displayId: id.rawValue, alias: nil, identityConfidence: 1.0,
                    operations: [.init(field: "reconnect", verification: ok ? .verified : .readBackUnavailable)]
                )
            }
        let status: ResultEnvelope.Status = results.isEmpty
            ? .noOp
            : (results.values.allSatisfy { $0 } ? .committed : .partial)
        return ResultEnvelope(
            transactionId: "txn_reconnectAll", status: status, actor: actor,
            requestedAt: Date(), topologyGeneration: snapshot.generation.value, targets: targets
        )
    }

    /// Runs a logical disconnect through the full staged transaction and returns its envelope.
    public func disconnect(_ target: DisplayRecordID, options: DisconnectOptions) async -> ResultEnvelope {
        do {
            let result = try await coordinator.disconnect(target, options: options)
            let after = await observer.currentSnapshot()
            return Self.envelope(for: result, target: target, actor: options.actor, generation: after.generation.value)
        } catch {
            let snapshot = await observer.currentSnapshot()
            return ResultEnvelope(
                transactionId: "txn_disconnect", status: .failed, actor: options.actor,
                requestedAt: Date(), topologyGeneration: snapshot.generation.value,
                errors: [.init(code: "coordinatorError", message: "\(error)")]
            )
        }
    }

    /// Preview a disconnect's preflight decision without mutating anything (`--dry-run`, confirm UI).
    public func preflightDisconnect(
        _ target: DisplayRecordID,
        identityConfidence: Double,
        recoveryServiceHealthy: Bool = true,
        isFirstUseForRoute: Bool = false
    ) async -> PreflightOutcome {
        let snapshot = await observer.currentSnapshot()
        let decision = safety.preflightDisconnect(
            target: target, snapshot: snapshot, identityConfidence: identityConfidence,
            recoveryServiceHealthy: recoveryServiceHealthy, isFirstUseForRoute: isFirstUseForRoute
        )
        switch decision {
        case .allowed(let surface):
            return PreflightOutcome(decision: .allowed, safeSurface: surface, reasons: [])
        case .needsConfirmation(let surface, let reasons):
            return PreflightOutcome(decision: .needsConfirmation, safeSurface: surface, reasons: reasons.map(\.rawValue))
        case .blocked(let reasons):
            return PreflightOutcome(decision: .blocked, safeSurface: nil, reasons: reasons.map(\.rawValue))
        }
    }

    public struct PreflightOutcome: Hashable, Sendable {
        public enum Decision: String, Hashable, Sendable { case allowed, needsConfirmation, blocked }
        public var decision: Decision
        public var safeSurface: DisplayRecordID?
        public var reasons: [String]
    }

    // MARK: - Result mapping

    /// Translates a coordinator `LifecycleResult` into a stable `ResultEnvelope`. Internal so tests
    /// can assert the mapping directly.
    static func envelope(
        for result: LifecycleResult, target: DisplayRecordID, actor: Actor, generation: UInt64
    ) -> ResultEnvelope {
        func make(_ status: ResultEnvelope.Status, _ transactionId: String,
                  verification: VerificationState = .notApplicable,
                  errors: [ResultEnvelope.ErrorInfo] = []) -> ResultEnvelope {
            ResultEnvelope(
                transactionId: transactionId, status: status, actor: actor, requestedAt: Date(),
                topologyGeneration: generation,
                targets: [.init(displayId: target.rawValue, alias: nil, identityConfidence: 1.0,
                                operations: [.init(field: "disconnect", verification: verification)])],
                errors: errors
            )
        }
        switch result {
        case .committed(let tx, let verification):
            return make(.committed, tx.rawValue, verification: verification)
        case .noOp(let tx):
            return make(.noOp, tx.rawValue)
        case .cancelled(let tx):
            return make(.noOp, tx.rawValue, errors: [.init(code: "cancelled", message: "confirmation declined")])
        case .rolledBack(let tx, let recovered):
            return make(.rolledBack, tx.rawValue, errors: [.init(code: "rolledBack", message: "recovered=\(recovered)")])
        case .failed(let tx, let failure):
            return make(.failed, tx.rawValue, errors: [.init(code: "providerFailure", message: "\(failure)")])
        case .blocked(let reasons):
            return make(.failed, "txn_blocked", errors: reasons.map { .init(code: "blocked", message: $0.rawValue) })
        }
    }
}
