#if os(macOS)
import DisplayDomain
import ProviderInterfaces

/// DDC/CI control over external monitors (PRD CTL-001..006/012/013). Stub — per-route VCP
/// probing, brightness/contrast/volume/input, timing, and read-back land in M1/M2. Reports
/// route-dependent `unknown` and refuses writes until implemented.
public struct DDCProvider: ControlProvider {
    public let providerID = "ddc.v1"
    public let isExperimental = false

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unknown, risk: .hardwareDependent, reasons: [.route])
    }

    public func capabilities(for target: DisplayRecordID, in environment: ProviderEnvironment) async -> [CapabilitySnapshot] {
        []
    }

    public func apply(_ capability: Capability, value: Double, to target: DisplayRecordID) async throws -> VerificationState {
        throw ProviderFailure.unsupported(reason: [.route])
    }

    public func read(_ capability: Capability, from target: DisplayRecordID) async throws -> Double? {
        nil
    }
}
#endif
