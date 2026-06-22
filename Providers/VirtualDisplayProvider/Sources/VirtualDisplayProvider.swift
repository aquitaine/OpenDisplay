#if os(macOS)
import DisplayDomain
import ProviderInterfaces

/// Labs-only software display endpoints (PRD VIR-001..003/007). Stub — disabled by default and
/// absent from the Core dependency graph; the real provider lands on the parallel Labs track.
public struct VirtualDisplayProvider: DisplayProvider {
    public let providerID = "virtualDisplay.v1"
    public let isExperimental = true

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unsupported, risk: .experimental, reasons: [.buildFlavor])
    }
}
#endif
