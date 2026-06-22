#if os(macOS)
import ColorSync  // CGDisplayGetDisplayIDFromUUID
import CoreGraphics
import DisplayDomain
import Foundation
import ProviderInterfaces

/// The isolated, separable logical connect/disconnect provider (PRD §9.9, §10.9, LIF-003/004).
///
/// M0 spike: the real mechanism is the **private SkyLight** entry point
/// `SLSConfigureDisplayEnabled` (historically `CGSConfigureDisplayEnabled`), which truly removes
/// a display from / restores it to the active arrangement on Apple Silicon. The symbols are
/// resolved with `dlsym` at runtime, so this compiles and links without a private-framework
/// dependency and **degrades to `.unsupported`** (rather than crashing or failing to link) when
/// the OS does not export them — letting the router fall back to the public mirroring provider.
///
/// This is undocumented and inherently `.recoveryCritical`; the target is **excluded from the
/// public-API-only build** (NFR-010 / D-008) and is Labs-gated. Success is never reported here —
/// the coordinator verifies observed postconditions (D-010).
public struct ExperimentalLifecycleProvider: LifecycleProvider {
    public let providerID = "experimentalLifecycle.v1"
    public let isExperimental = true

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias ConfigureEnabledFn = @convention(c) (Int32, CGDirectDisplayID, Bool) -> Int32

    private let mainConnection: MainConnectionFn?
    private let configureEnabled: ConfigureEnabledFn?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        // Newer (SLS*) names first, then the legacy CGS* aliases.
        mainConnection =
            Self.lookup(handle, "SLSMainConnectionID", as: MainConnectionFn.self)
            ?? Self.lookup(handle, "CGSMainConnectionID", as: MainConnectionFn.self)
        configureEnabled =
            Self.lookup(handle, "SLSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
            ?? Self.lookup(handle, "CGSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
    }

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        // The SkyLight symbols resolve, but the bare 3-arg call is the wrong ABI (see setEnabled),
        // so until the CGS display-configuration transaction is implemented and verified we report
        // unsupported and let RoutedLifecycleProvider fall back to the public mirroring provider.
        _ = (mainConnection, configureEnabled)
        return ProviderProbe(
            providerID: providerID,
            status: .unsupported,
            risk: .recoveryCritical,
            reasons: environment.isAppleSilicon ? [.osVersion] : [.architecture]
        )
    }

    public func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try setEnabled(target, enabled: false)
    }

    public func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try setEnabled(target, enabled: true)
    }

    public func recover(to checkpoint: Checkpoint) async throws {
        // Best effort: re-enable every display the checkpoint recorded as active.
        for observation in checkpoint.observations where observation.isActive {
            try? setEnabled(observation.recordID, enabled: true)
        }
    }

    // MARK: - Private

    private func setEnabled(_ target: DisplayRecordID, enabled: Bool) throws {
        // NOT IMPLEMENTED — and deliberately not called. A bare
        // `SLSConfigureDisplayEnabled(cid, displayID, enabled)` segfaults inside
        // `checkCapacity(CGSConfigData*)`: the real entry point takes a CGS display-configuration
        // transaction object (a begin → configure → complete sequence, like the public
        // CGBeginDisplayConfiguration flow), not a bare display ID. Implementing and verifying that
        // sequence is a follow-up; until then this throws `.unsupported` so RoutedLifecycleProvider
        // falls back to the public CoreGraphicsProvider mirroring path. (Verified 2026-06-22: the
        // 3-arg call crashes on macOS / Apple Silicon.)
        _ = (target, enabled)
        throw ProviderFailure.unsupported(reason: [.osVersion])
    }

    private static func lookup<T>(_ handle: UnsafeMutableRawPointer?, _ symbol: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// Resolves an app record ID to a live `CGDirectDisplayID`. Mirrors the record-ID convention
    /// minted by `CoreGraphicsProvider` (`cg:<uuid>` / `cgid:<n>`); kept local to avoid a
    /// provider-to-provider dependency.
    private static func displayID(for record: DisplayRecordID) -> CGDirectDisplayID? {
        let raw = record.rawValue
        if raw.hasPrefix("cgid:") { return UInt32(raw.dropFirst("cgid:".count)) }
        if raw.hasPrefix("cg:") {
            let uuidString = String(raw.dropFirst("cg:".count))
            guard let uuid = CFUUIDCreateFromString(kCFAllocatorDefault, uuidString as CFString) else { return nil }
            let id = CGDisplayGetDisplayIDFromUUID(uuid)
            return id != 0 ? id : nil
        }
        return nil
    }
}
#endif
