import Foundation

/// A remembered display that OpenDisplay intentionally placed offline. Distinct from system
/// absence (PRD §13.1, LIF-022). Carries who/when/why and the desired reconnect policy.
public struct ManagedOfflineRecord: Hashable, Sendable, Codable, Identifiable {
    public var id: DisplayRecordID { displayID }
    public var displayID: DisplayRecordID
    public var actor: Actor
    public var reason: String
    public var disconnectedAt: Date
    public var providerID: String
    public var persistencePolicy: PersistencePolicy
    public var lastFailure: String?

    public init(
        displayID: DisplayRecordID,
        actor: Actor,
        reason: String,
        disconnectedAt: Date = Date(),
        providerID: String,
        persistencePolicy: PersistencePolicy = .reconnectOnQuit,
        lastFailure: String? = nil
    ) {
        self.displayID = displayID
        self.actor = actor
        self.reason = reason
        self.disconnectedAt = disconnectedAt
        self.providerID = providerID
        self.persistencePolicy = persistencePolicy
        self.lastFailure = lastFailure
    }
}

/// Persistence is a desired-state policy the app reapplies — never an OS guarantee (PRD §9.8,
/// LIF-015). Persistent disconnect is off by default.
public enum PersistencePolicy: String, Hashable, Sendable, Codable {
    /// Reconnect on normal quit, wake, and reboot (the safe default, D-005).
    case reconnectOnQuit
    /// Reconnect only on wake, otherwise stay offline.
    case reconnectOnWake
    /// Opt-in: try to stay offline across login/reboot once health checks pass.
    case persistentOffline
}

/// The minimal, rescue-readable snapshot written before any risky transaction (PRD §9.4,
/// DIA-008). Kept small and free of secrets so the standalone rescue utility can restore it.
public struct Checkpoint: Hashable, Sendable, Codable, Identifiable {
    public var id: CheckpointID
    public var transactionID: TransactionID
    public var generation: TopologyGeneration
    public var observations: [DisplayObservation]
    public var mainDisplayID: DisplayRecordID?
    public var managedOffline: [ManagedOfflineRecord]
    public var createdAt: Date

    public init(
        id: CheckpointID = .generate(),
        transactionID: TransactionID,
        generation: TopologyGeneration,
        observations: [DisplayObservation],
        mainDisplayID: DisplayRecordID? = nil,
        managedOffline: [ManagedOfflineRecord] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transactionID = transactionID
        self.generation = generation
        self.observations = observations
        self.mainDisplayID = mainDisplayID
        self.managedOffline = managedOffline
        self.createdAt = createdAt
    }
}

/// Health of a provider for a given environment key. Three bounded failures trip the circuit
/// breaker and disable the provider (PRD DIA-007, §9.2 invariant 10).
// TODO(DIA-007): implemented but not yet wired — no capability gate or health store consumes it.
// Tracks PRD DIA-007 / §9.2 invariant 10 (disable a failing provider after 3 bounded failures
// and stop destabilizing writes).
public struct ProviderHealth: Hashable, Sendable, Codable {
    public enum Status: String, Hashable, Sendable, Codable {
        case ok
        case degraded
        case circuitOpen
        case unknown
    }

    public var providerID: String
    public var environmentKey: String
    public var status: Status
    public var consecutiveFailures: Int
    public var lastProbe: Date?

    public static let failureThreshold = 3

    public init(
        providerID: String,
        environmentKey: String,
        status: Status = .unknown,
        consecutiveFailures: Int = 0,
        lastProbe: Date? = nil
    ) {
        self.providerID = providerID
        self.environmentKey = environmentKey
        self.status = status
        self.consecutiveFailures = consecutiveFailures
        self.lastProbe = lastProbe
    }

    /// Returns a copy reflecting one more failure, tripping the breaker at the threshold.
    public func recordingFailure(now: Date = Date()) -> ProviderHealth {
        let failures = consecutiveFailures + 1
        return ProviderHealth(
            providerID: providerID,
            environmentKey: environmentKey,
            status: failures >= Self.failureThreshold ? .circuitOpen : .degraded,
            consecutiveFailures: failures,
            lastProbe: now
        )
    }

    /// Returns a copy reset to healthy after a success.
    public func recordingSuccess(now: Date = Date()) -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            environmentKey: environmentKey,
            status: .ok,
            consecutiveFailures: 0,
            lastProbe: now
        )
    }

    public var isUsable: Bool { status != .circuitOpen }
}

/// An immutable snapshot of the whole normalized topology at a generation. This is what the UI
/// consumes and what the planner/safety engine reason over (PRD §10.4).
public struct TopologySnapshot: Hashable, Sendable, Codable {
    public var generation: TopologyGeneration
    public var observations: [DisplayObservation]
    public var managedOffline: [ManagedOfflineRecord]
    public var capturedAt: Date

    public init(
        generation: TopologyGeneration,
        observations: [DisplayObservation],
        managedOffline: [ManagedOfflineRecord] = [],
        capturedAt: Date = Date()
    ) {
        self.generation = generation
        self.observations = observations
        self.managedOffline = managedOffline
        self.capturedAt = capturedAt
    }

    public var activeDisplays: [DisplayObservation] {
        observations.filter { $0.isActive }
    }

    public func observation(for id: DisplayRecordID) -> DisplayObservation? {
        observations.first { $0.recordID == id }
    }
}
