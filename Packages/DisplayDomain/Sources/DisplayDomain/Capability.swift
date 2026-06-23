import Foundation

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
