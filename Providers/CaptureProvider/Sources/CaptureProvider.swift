#if os(macOS)
import DisplayDomain
import ProviderInterfaces

/// ScreenCaptureKit-backed PIP / zoom / screenshots (PRD VIR-004..007, Core 1.x). Stub — capture
/// sessions and permission handling land in M4. Requests no permission until a capture feature runs.
public struct CaptureProvider: DisplayProvider {
    public let providerID = "capture.v1"
    public let isExperimental = false

    public init() {}

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unknown, risk: .normal, reasons: [.permission])
    }
}
#endif
