#if os(macOS)
import DisplayDomain
import Foundation
import ProviderInterfaces

/// Public display enumeration and configuration via Core Graphics (PRD §10.3, TOP-001/002/003).
///
/// Stub — real enumeration, modes, mirror/main configuration, and a `TopologyObserving` event
/// source land in M0. Until then it probes as `unknown` so the app degrades safely.
public struct CoreGraphicsProvider: DisplayProvider {
    public let providerID = "coregraphics.v1"
    public let isExperimental = false

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unknown, risk: .normal)
    }
}
#endif
