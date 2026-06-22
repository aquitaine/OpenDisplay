#if os(macOS)
import DisplayDomain
import ProviderInterfaces

/// Native Apple/built-in brightness + audio, plus a software dimmer below the hardware minimum
/// (PRD CTL-001/003/004). Stub — real control lands in M1/M2.
public struct NativeControlProvider: ControlProvider {
    public let providerID = "native.v1"
    public let isExperimental = false

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unknown, risk: .normal)
    }

    public func capabilities(for target: DisplayRecordID, in environment: ProviderEnvironment) async -> [CapabilitySnapshot] {
        []
    }

    public func apply(_ capability: Capability, value: Double, to target: DisplayRecordID) async throws -> VerificationState {
        throw ProviderFailure.unsupported(reason: [.providerHealth])
    }

    public func read(_ capability: Capability, from target: DisplayRecordID) async throws -> Double? {
        nil
    }
}
#endif
