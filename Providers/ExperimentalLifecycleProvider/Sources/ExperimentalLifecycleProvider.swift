#if os(macOS)
import DisplayDomain
import Foundation
import ProviderInterfaces

/// The isolated, separable logical connect/disconnect provider (PRD §9.9, §10.9, LIF-003/004).
///
/// Stub — the M0 spike implements the real mechanism on a certified Apple Silicon configuration.
/// Until then it probes as `.unsupported` (risk `.recoveryCritical`) and refuses every mutation,
/// so the coordinator's preflight blocks safely. This target is **excluded from the
/// public-API-only build** (NFR-010 / D-008).
public struct ExperimentalLifecycleProvider: LifecycleProvider {
    public let providerID = "experimentalLifecycle.v1"
    public let isExperimental = true

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unsupported, risk: .recoveryCritical, reasons: [.buildFlavor])
    }

    public func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }

    public func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }

    public func recover(to checkpoint: Checkpoint) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }
}
#endif
