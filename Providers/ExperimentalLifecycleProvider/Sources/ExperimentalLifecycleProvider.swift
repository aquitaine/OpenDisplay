#if os(macOS)
import ColorSync  // CGDisplayGetDisplayIDFromUUID
import CoreGraphics
import DisplayDomain
import Foundation
import ProviderInterfaces

/// The isolated, separable logical connect/disconnect provider (PRD §9.9, §10.9, LIF-003/004).
///
/// Real mechanism: a **fully private CGS/SkyLight display-configuration transaction**. There is no
/// public API to remove a display from the active arrangement, so this drives the same three-step
/// shape the public `CGBeginDisplayConfiguration` flow uses, but with the SkyLight functions whose
/// signatures were recovered by disassembly (macOS 26 / SkyLight; no connection ID, config first):
///
///   1. `SLSBeginDisplayConfiguration(&config)`             — allocates a SkyLight `CGSConfigData`
///   2. `SLSConfigureDisplayEnabled(config, displayID, enabled)` — appends an enable/disable entry
///   3. `SLSCompleteDisplayConfigurationWithOption(config, option)` — commit + free
///
/// The config object MUST come from `SLSBeginDisplayConfiguration` (it carries a `0xbeefcafe`
/// capacity header that `checkCapacity` validates) — the public `CGDisplayConfigRef` is a different
/// object, and a `(cid, displayID, enabled)` call with no config segfaults in
/// `checkCapacity(CGSConfigData*)`. Disabling a display makes `CGGetActiveDisplayList` drop it — a
/// true logical disconnect, unlike mirroring.
///
/// The private symbols are resolved with `dlsym` at runtime, so this links without a
/// private-framework dependency and **degrades to `.unsupported`** when a symbol is absent — the
/// router then falls back to the public mirroring provider. Undocumented and inherently
/// `.recoveryCritical`; excluded from the public-API-only build (NFR-010 / D-008) and Labs-gated.
/// Committed with the `forAppOnly` option, so the change reverts automatically if OpenDisplay exits
/// (matching the reconnect-on-quit default, D-005) — a strong safety net on top of the
/// coordinator's checkpoint/rollback and the independent rescue utility. Success is never reported
/// here — the coordinator verifies observed postconditions (D-010).
public struct ExperimentalLifecycleProvider: LifecycleProvider {
    public let providerID = "experimentalLifecycle.v1"
    public let isExperimental = true

    /// `(CGSConfigData **out) -> CGError` — one out-param, no connection ID.
    private typealias BeginFn = @convention(c) (UnsafeMutablePointer<OpaquePointer?>) -> Int32
    /// `(CGSConfigData *config, CGDirectDisplayID display, bool enabled) -> CGError` — config FIRST.
    private typealias ConfigureEnabledFn = @convention(c) (OpaquePointer?, CGDirectDisplayID, Bool) -> Int32
    /// `(CGSConfigData *config, CGSConfigureOption option) -> CGError` (option: 0=appOnly,1=session,2=permanent).
    private typealias CompleteFn = @convention(c) (OpaquePointer?, Int32) -> Int32
    /// `(CGSConfigData *config) -> CGError` — discards a transaction (best-effort cleanup on error).
    private typealias CancelFn = @convention(c) (OpaquePointer?) -> Int32

    private let beginConfig: BeginFn?
    private let configureEnabled: ConfigureEnabledFn?
    private let completeConfig: CompleteFn?
    private let cancelConfig: CancelFn?

    /// `forAppOnly`: the enable/disable reverts when this process exits.
    private static let optionAppOnly: Int32 = 0

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        // Newer (SLS*) names first, then the legacy CGS* aliases.
        beginConfig =
            Self.lookup(handle, "SLSBeginDisplayConfiguration", as: BeginFn.self)
            ?? Self.lookup(handle, "CGSBeginDisplayConfiguration", as: BeginFn.self)
        configureEnabled =
            Self.lookup(handle, "SLSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
            ?? Self.lookup(handle, "CGSConfigureDisplayEnabled", as: ConfigureEnabledFn.self)
        completeConfig =
            Self.lookup(handle, "SLSCompleteDisplayConfigurationWithOption", as: CompleteFn.self)
            ?? Self.lookup(handle, "CGSCompleteDisplayConfigurationWithOption", as: CompleteFn.self)
        cancelConfig =
            Self.lookup(handle, "SLSCancelDisplayConfiguration", as: CancelFn.self)
            ?? Self.lookup(handle, "CGSCancelDisplayConfiguration", as: CancelFn.self)
    }

    public func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        guard beginConfig != nil, configureEnabled != nil, completeConfig != nil else {
            return ProviderProbe(providerID: providerID, status: .unsupported,
                                 risk: .recoveryCritical, reasons: [.osVersion])
        }
        guard environment.isAppleSilicon else {
            return ProviderProbe(providerID: providerID, status: .unsupported,
                                 risk: .recoveryCritical, reasons: [.architecture])
        }
        return ProviderProbe(providerID: providerID, status: .supported, risk: .recoveryCritical)
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

    /// Runs one SkyLight display-config transaction that sets `target`'s enabled flag.
    /// `enabled == false` is a true logical disconnect (the display leaves the active arrangement);
    /// `true` restores it.
    private func setEnabled(_ target: DisplayRecordID, enabled: Bool) throws {
        guard let beginConfig, let configureEnabled, let completeConfig else {
            throw ProviderFailure.unsupported(reason: [.osVersion])
        }
        guard let displayID = Self.displayID(for: target) else {
            throw ProviderFailure.ambiguous(candidates: [])
        }

        var config: OpaquePointer?
        let beginStatus = beginConfig(&config)
        guard beginStatus == 0, let config else {
            throw ProviderFailure.osRejected(code: Int(beginStatus))
        }
        let configureStatus = configureEnabled(config, displayID, enabled)
        guard configureStatus == 0 else {
            _ = cancelConfig?(config)  // best-effort: discard + free the aborted transaction
            throw ProviderFailure.osRejected(code: Int(configureStatus))
        }
        let completeStatus = completeConfig(config, Self.optionAppOnly)
        guard completeStatus == 0 else {
            throw ProviderFailure.osRejected(code: Int(completeStatus))
        }
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
