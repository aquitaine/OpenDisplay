import Foundation

/// The set of capabilities OpenDisplay reasons about. Support is contextual — it depends on
/// Mac, OS, display, route, permission, build flavor, provider health, and policy (PRD §2.1).
public enum Capability: String, Hashable, Sendable, Codable, CaseIterable {
    case logicalDisconnect
    case logicalReconnect
    case blackOut
    case monitorPower
    case nativeBrightness
    case ddcBrightness
    case softwareDimming
    case volume
    case contrast
    case inputSource
    case rotation
    case mirroring
    case hdrRead
    case hdrWrite
    case colorProfile
    case virtualDisplay
    case capture
}

public enum CapabilityStatus: String, Hashable, Sendable, Codable {
    case supported
    case unsupported
    case unknown
    case degraded
    case disabledByPolicy
}

/// Whether an applied change could actually be confirmed. A provider call is not success
/// (PRD §2.1 "Verify, do not assume"; D-010).
public enum VerificationState: String, Hashable, Sendable, Codable {
    case verified
    case readBackUnavailable
    case notApplicable
}

public enum RiskLevel: String, Hashable, Sendable, Codable, Comparable {
    case normal
    case hardwareDependent
    case experimental
    case recoveryCritical

    private var order: Int {
        switch self {
        case .normal: return 0
        case .hardwareDependent: return 1
        case .experimental: return 2
        case .recoveryCritical: return 3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.order < rhs.order }
}

/// Why a capability is in its current state. Every unavailable feature must carry at least one
/// reason so the UI/API can explain it (PRD DIA-004, DIA-006).
public enum CapabilityReason: String, Hashable, Sendable, Codable {
    case osVersion
    case architecture
    case displayClass
    case route
    case permission
    case buildFlavor
    case providerHealth
    case userPolicy
    case safetyPolicy
}

/// A contextual capability decision, valid only for the topology generation in which it was
/// computed (PRD §10.6). Invalidated by route/OS/provider changes.
public struct CapabilitySnapshot: Hashable, Sendable, Codable {
    public var capability: Capability
    public var status: CapabilityStatus
    public var verification: VerificationState
    public var risk: RiskLevel
    public var providerID: String?
    public var reasons: [CapabilityReason]
    public var validForGeneration: TopologyGeneration

    public init(
        capability: Capability,
        status: CapabilityStatus,
        verification: VerificationState = .notApplicable,
        risk: RiskLevel = .normal,
        providerID: String? = nil,
        reasons: [CapabilityReason] = [],
        validForGeneration: TopologyGeneration
    ) {
        self.capability = capability
        self.status = status
        self.verification = verification
        self.risk = risk
        self.providerID = providerID
        self.reasons = reasons
        self.validForGeneration = validForGeneration
    }

    public var isUsable: Bool {
        status == .supported || status == .degraded
    }
}
