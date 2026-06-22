import DisplayDomain
import Foundation

/// The typed failure vocabulary every provider shares (PRD §9.9 failure semantics). A provider
/// can never report success itself; the coordinator verifies postconditions (D-010).
public enum ProviderFailure: Error, Equatable, Sendable {
    case unsupported(reason: [CapabilityReason])
    case denied
    case ambiguous(candidates: [DisplayRecordID])
    case busy
    case timeout
    case osRejected(code: Int)
    case providerError(message: String)
    case partial(message: String)
    case unknown
}

/// The probe result a provider returns for an environment (PRD §9.9 `probe`). Must not mutate.
public struct ProviderProbe: Hashable, Sendable {
    public var providerID: String
    public var status: CapabilityStatus
    public var risk: RiskLevel
    public var reasons: [CapabilityReason]
    public var supportedOSRange: String?

    public init(
        providerID: String,
        status: CapabilityStatus,
        risk: RiskLevel,
        reasons: [CapabilityReason] = [],
        supportedOSRange: String? = nil
    ) {
        self.providerID = providerID
        self.status = status
        self.risk = risk
        self.reasons = reasons
        self.supportedOSRange = supportedOSRange
    }
}

/// The environment a provider is asked to evaluate itself against (OS build, architecture, route…).
public struct ProviderEnvironment: Hashable, Sendable {
    public var osBuild: String
    public var isAppleSilicon: Bool
    public var transport: ConnectionTransport
    public var displayClass: DisplayClass

    public init(osBuild: String, isAppleSilicon: Bool, transport: ConnectionTransport, displayClass: DisplayClass) {
        self.osBuild = osBuild
        self.isAppleSilicon = isAppleSilicon
        self.transport = transport
        self.displayClass = displayClass
    }
}

/// Base provider behavior shared across all provider kinds.
public protocol DisplayProvider: Sendable {
    var providerID: String { get }
    /// Whether this provider relies on undocumented/private behavior and must be Labs-gated and
    /// kept out of the public-API-only build (PRD §2.3, OSS-02).
    var isExperimental: Bool { get }
    /// Pure capability probe — must not mutate any display state (PRD §9.9).
    func probe(_ environment: ProviderEnvironment) async -> ProviderProbe
}

/// The lifecycle provider that performs logical connect/disconnect. The most safety-sensitive
/// contract in the system; isolated behind this protocol so it can be compiled, tested, disabled,
/// or replaced independently (PRD §9.9, §10.9, LIF-003/004).
public protocol LifecycleProvider: DisplayProvider {
    /// Requests logical removal of `target` from the active topology before `deadline`. Cancellation
    /// aware. Throws `ProviderFailure`; success is decided by the coordinator's verifier, not here.
    func disconnect(_ target: DisplayRecordID, deadline: Date) async throws

    /// Requests reactivation. Must tolerate an already-active target and be idempotent.
    func reconnect(_ target: DisplayRecordID, deadline: Date) async throws

    /// Optional optimized bulk path; the coordinator still verifies each target individually.
    func reconnectAll(_ candidates: [DisplayRecordID], deadline: Date) async throws

    /// Best-effort emergency restoration usable with minimal dependencies (PRD §9.9 `recover`).
    func recover(to checkpoint: Checkpoint) async throws
}

public extension LifecycleProvider {
    func reconnectAll(_ candidates: [DisplayRecordID], deadline: Date) async throws {
        for candidate in candidates {
            try await reconnect(candidate, deadline: deadline)
        }
    }
}

/// A control provider (native/DDC/software/network) for brightness, volume, contrast, input, etc.
public protocol ControlProvider: DisplayProvider {
    func capabilities(for target: DisplayRecordID, in environment: ProviderEnvironment) async -> [CapabilitySnapshot]
    /// Applies a normalized 0...100 value for a capability, returning whether it could be verified.
    func apply(_ capability: Capability, value: Double, to target: DisplayRecordID) async throws -> VerificationState
    /// Reads back a normalized 0...100 value where supported.
    func read(_ capability: Capability, from target: DisplayRecordID) async throws -> Double?
}

/// Reads the normalized observed topology. Implemented on macOS by the DisplayRegistry's event
/// source; the coordinator depends only on this protocol so its logic stays platform-independent.
public protocol TopologyObserving: Sendable {
    func currentSnapshot() async -> TopologySnapshot
    /// Awaits the next stabilized topology generation correlated with a transaction (PRD §9.5).
    func awaitStableGeneration(after generation: TopologyGeneration) async -> TopologySnapshot
}
