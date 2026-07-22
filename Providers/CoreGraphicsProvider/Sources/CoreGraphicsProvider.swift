#if os(macOS)
import ColorSync  // CGDisplayCreateUUIDFromDisplayID is declared here, not in CoreGraphics
import CoreGraphics
import DisplayDomain
import Foundation
import ProviderInterfaces

/// Top-level C callback for `CGDisplayRegisterReconfigurationCallback`. It must be a
/// non-capturing function so it bridges to a `@convention(c)` pointer; the owning provider is
/// recovered from `userInfo`. Runs on the registering thread's run loop (the app's main loop).
private func openDisplayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let provider = Unmanaged<CoreGraphicsProvider>.fromOpaque(userInfo).takeUnretainedValue()
    let raw = flags.rawValue
    Task { await provider.handleReconfiguration(rawFlags: raw) }
}

/// Public display enumeration via Core Graphics, exposed as the platform-independent
/// `TopologyObserving` the coordinator depends on (PRD §10.3, TOP-001/002/003).
///
/// This is the M0 observation source: it enumerates the real online displays, normalizes them
/// into `DisplayObservation`s, and advances the `TopologyGeneration` whenever the topology
/// signature changes — driven both lazily (each snapshot) and eagerly by a
/// `CGDisplayRegisterReconfigurationCallback` event source so hotplug/rotation/mirror changes are
/// noticed promptly.
///
/// It also serves as the **public, reversible** `LifecycleProvider` fallback: lacking a public
/// API to truly remove a display, it approximates logical disconnect by mirroring the target into
/// the safe surface via `CGConfigureDisplayMirrorOfDisplay` (un-mirroring on reconnect). The true
/// logical disconnect lives in the experimental SkyLight provider; the router prefers that and
/// falls back here. Only documented Apple APIs are used, so this provider stays in the
/// public-API-only build (NFR-010, D-008).
public actor CoreGraphicsProvider: TopologyObserving, DisplayProvider, LifecycleProvider {
    public nonisolated let providerID = "coregraphics.v1"
    public nonisolated let isExperimental = false

    private var generation: TopologyGeneration = .initial
    private var lastSignature = ""
    /// Opaque retained-self token while the OS reconfiguration callback is registered; nil otherwise.
    /// Retaining self keeps the instance alive across an in-flight callback, so a topology event can
    /// never resurrect a deallocating provider.
    private var observingToken: UnsafeMutableRawPointer?

    public init() {}
    // No deinit: startObserving() takes a +1 self-retain, so a registered observer is kept alive by the
    // OS for the app's lifetime and can never deinit mid-callback (closing the resurrection race); an
    // un-registered provider (intents/CLI/rescue) holds no callback, so there is nothing to clean up.

    /// Begins delivering reconfiguration events to `changes()` subscribers. Idempotent. Only the
    /// long-lived observer that consumes the stream registers; short-lived providers (App Intents,
    /// CLI, one-shot rescue) never call this, so their teardown can't race the global callback table.
    public func startObserving() {
        guard observingToken == nil else { return }
        let token = Unmanaged.passRetained(self).toOpaque()
        observingToken = token
        CGDisplayRegisterReconfigurationCallback(openDisplayReconfigurationCallback, token)
    }

    /// Stops delivering events and balances the self-retain taken in `startObserving`.
    public func stopObserving() {
        guard let token = observingToken else { return }
        CGDisplayRemoveReconfigurationCallback(openDisplayReconfigurationCallback, token)
        observingToken = nil
        Unmanaged<CoreGraphicsProvider>.fromOpaque(token).release()
    }

    // MARK: TopologyObserving

    public func currentSnapshot() -> TopologySnapshot {
        currentTopology()
    }

    /// Polls the live topology until the generation advances past `generation` or a short deadline
    /// elapses. Actor reentrancy lets the reconfiguration callback (and lazy re-enumeration) run
    /// during the sleeps; the timeout guarantees the coordinator never blocks if the OS emits no
    /// event (e.g. a logical op that silently no-ops).
    public func awaitStableGeneration(after generation: TopologyGeneration) async -> TopologySnapshot {
        let stepNanos: UInt64 = 100_000_000      // 100 ms
        let timeoutNanos: UInt64 = 2_000_000_000  // 2 s
        var waited: UInt64 = 0
        var snapshot = currentTopology()
        while snapshot.generation <= generation && waited < timeoutNanos {
            try? await Task.sleep(nanoseconds: stepNanos)
            waited += stepNanos
            snapshot = currentTopology()
        }
        return snapshot
    }

    // MARK: DisplayProvider

    public func probe(_ environment: ProviderEnvironment) -> ProviderProbe {
        // Public display enumeration is available on every supported macOS.
        ProviderProbe(providerID: providerID, status: .supported, risk: .normal)
    }

    // MARK: LifecycleProvider (public, reversible — mirroring fallback)

    /// Approximates a logical disconnect by mirroring `target` into the current main display, so
    /// it stops being an independent surface. Reversible via `reconnect`. Refuses to mirror the
    /// main display onto itself (the coordinator independently guarantees a safe surface remains).
    public func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        guard let id = Self.displayID(for: target) else { throw ProviderFailure.ambiguous(candidates: []) }
        let master = CGMainDisplayID()
        guard id != master else { throw ProviderFailure.unsupported(reason: [.safetyPolicy]) }
        try applyMirror(of: id, onto: master)
    }

    /// Un-mirrors `target`, restoring it as an independent display. Idempotent: un-mirroring a
    /// display that is not mirrored is a successful no-op.
    public func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        guard let id = Self.displayID(for: target) else { throw ProviderFailure.ambiguous(candidates: []) }
        try applyMirror(of: id, onto: kCGNullDirectDisplay)
    }

    /// Best-effort restoration: un-mirror every display the checkpoint recorded as active, so the
    /// independent arrangement comes back.
    public func recover(to checkpoint: Checkpoint) async throws {
        for observation in checkpoint.observations where observation.isActive {
            guard let id = Self.displayID(for: observation.recordID) else { continue }
            try? applyMirror(of: id, onto: kCGNullDirectDisplay)
        }
    }

    /// Resolves an app record ID back to a live `CGDirectDisplayID`. The `cg:<uuid>` form is
    /// resolved through the persistent CG UUID (stable across reboots); `cgid:<n>` is the raw ID.
    public nonisolated static func displayID(for record: DisplayRecordID) -> CGDirectDisplayID? {
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

    /// Runs one mirror (re)configuration inside a CG display-configuration transaction. Pass
    /// `kCGNullDirectDisplay` as the master to un-mirror. Applied `.forSession` so any mistake
    /// self-heals at logout — an extra safety net beyond the coordinator's checkpoint/rollback.
    private func applyMirror(of display: CGDirectDisplayID, onto master: CGDirectDisplayID) throws {
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            throw ProviderFailure.osRejected(code: -1)
        }
        let configureError = CGConfigureDisplayMirrorOfDisplay(config, display, master)
        guard configureError == .success else {
            CGCancelDisplayConfiguration(config)
            throw ProviderFailure.osRejected(code: Int(configureError.rawValue))
        }
        let completeError = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeError == .success else {
            throw ProviderFailure.osRejected(code: Int(completeError.rawValue))
        }
    }

    /// Software-dims a display by scaling its gamma transfer ramp (`level` 0.15...1, where 1 = no
    /// dim). Works on any display — including externals without DDC and below the hardware minimum.
    /// Floored so the screen can never go fully black. Public Core Graphics (CGSetDisplayTransferByFormula).
    public nonisolated func setGammaDim(_ level: Float, for displayID: CGDirectDisplayID) {
        setGammaAdjustment(dim: level, red: 1, green: 1, blue: 1, for: displayID)
    }

    /// The combined software gamma write: one dim scale times per-channel colour-temperature gains
    /// (each 0...1). Dim and warmth share the single `CGSetDisplayTransferByFormula` slot per
    /// display, so every gamma-touching path must come through here (or `setGammaDim`, its
    /// neutral-colour wrapper) — separate calls would silently overwrite each other.
    public nonisolated func setGammaAdjustment(
        dim: Float, red: Float, green: Float, blue: Float, for displayID: CGDirectDisplayID
    ) {
        setGammaAdjustment(dim: dim, red: red, green: green, blue: blue, boost: 1, for: displayID)
    }

    /// `setGammaAdjustment` with an XDR brightness boost (≥ 1) multiplied in. The formula API
    /// clamps its coefficients to 1.0, so a boost — which maps EDR-attenuated SDR content back up
    /// toward full drive of the raised backlight — can only be expressed as an explicit transfer
    /// TABLE: the same linear ramp the formula produces, times `boost`, saturating at 1. With no
    /// meaningful boost this delegates to the formula path, so existing behavior is untouched.
    /// Like the formula path, the table is an absolute re-expression from the app's own state
    /// (never a scale of the current hardware table), so repeated writes can't compound.
    public nonisolated func setGammaAdjustment(
        dim: Float, red: Float, green: Float, blue: Float, boost: Float,
        for displayID: CGDirectDisplayID
    ) {
        let scale = CGGammaValue(max(0.15, min(1, dim)))
        let r = scale * CGGammaValue(min(max(red, 0), 1))
        let g = scale * CGGammaValue(min(max(green, 0), 1))
        let b = scale * CGGammaValue(min(max(blue, 0), 1))
        guard boost > 1.001 else {
            _ = CGSetDisplayTransferByFormula(displayID, 0, r, 1, 0, g, 1, 0, b, 1)
            return
        }
        let count = 256
        var redTable = [CGGammaValue](repeating: 0, count: count)
        var greenTable = [CGGammaValue](repeating: 0, count: count)
        var blueTable = [CGGammaValue](repeating: 0, count: count)
        for i in 0..<count {
            let input = CGGammaValue(i) / CGGammaValue(count - 1) * CGGammaValue(boost)
            redTable[i] = min(1, input * r)
            greenTable[i] = min(1, input * g)
            blueTable[i] = min(1, input * b)
        }
        _ = CGSetDisplayTransferByTable(displayID, UInt32(count), redTable, greenTable, blueTable)
    }

    /// Restores every display's gamma to its ColorSync calibration, clearing any software dim. Call
    /// on quit so a dim never outlives the app.
    public nonisolated static func restoreGamma() {
        CGDisplayRestoreColorSyncSettings()
    }

    /// Mirrors `displayID` onto the current main display (both show the same content), or stops
    /// mirroring when `enabled` is false. Reversible; public Core Graphics only.
    public func setMirroring(of displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
        let master = enabled ? CGMainDisplayID() : kCGNullDirectDisplay
        do {
            try applyMirror(of: displayID, onto: master)
            return true
        } catch {
            return false
        }
    }

    // MARK: Reconfiguration event source

    private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Emits whenever the live topology changes (hotplug, unplug, sleep, rotation, mirror,
    /// enable/disable). The app subscribes to refresh promptly and to enforce the
    /// always-one-active-display invariant when a display is physically unplugged.
    public func changes() -> AsyncStream<Void> {
        startObserving()  // lazily register the OS callback on the first (long-lived) subscriber
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        changeContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.dropContinuation(id) }
        }
        return stream
    }

    private func dropContinuation(_ id: UUID) { changeContinuations[id] = nil }

    /// Invoked off the CG reconfiguration callback. Recomputing the topology bumps the generation
    /// if the signature changed; redundant callbacks (e.g. the begin-configuration phase) are
    /// harmless no-ops because the signature is unchanged. Subscribers are then notified.
    func handleReconfiguration(rawFlags: UInt32) {
        // The begin-configuration callback fires *before* the change lands (and while another app may
        // hold the configuration), so the display list is mid-flight. React only to settled callbacks.
        let flags = CGDisplayChangeSummaryFlags(rawValue: rawFlags)
        if flags.contains(.beginConfigurationFlag) { return }
        _ = currentTopology()
        for continuation in changeContinuations.values { continuation.yield(()) }
    }

    // MARK: - Enumeration

    private func currentTopology() -> TopologySnapshot {
        let ids = onlineDisplayIDs()
        let signature = topologySignature(of: ids)
        if signature != lastSignature {
            lastSignature = signature
            generation = generation.next()
        }
        let now = Date()
        let observations = ids.map { observation(for: $0, generation: generation, at: now) }
        return TopologySnapshot(generation: generation, observations: observations, capturedAt: now)
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 32
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func observation(
        for id: CGDirectDisplayID,
        generation: TopologyGeneration,
        at now: Date
    ) -> DisplayObservation {
        let uuid = displayUUID(id)
        let isBuiltin = CGDisplayIsBuiltin(id) != 0
        let bounds = CGDisplayBounds(id)
        let mirrorMaster = CGDisplayMirrorsDisplay(id)
        let mirrorSourceID = mirrorMaster != 0
            ? recordID(uuid: displayUUID(mirrorMaster), id: mirrorMaster)
            : nil
        return DisplayObservation(
            recordID: recordID(uuid: uuid, id: id),
            cgDisplayID: id,
            cgUUID: uuid,
            isActive: CGDisplayIsActive(id) != 0,
            origin: DisplayOrigin(x: Int(bounds.origin.x), y: Int(bounds.origin.y)),
            mode: CGDisplayCopyDisplayMode(id).map(displayMode(from:)),
            rotation: rotation(of: id),
            isMain: CGDisplayIsMain(id) != 0,
            mirrorSourceID: mirrorSourceID,
            transport: isBuiltin ? .internalPanel : .unknown,
            displayClass: isBuiltin ? .builtIn : .external,
            generation: generation,
            observedAt: now
        )
    }

    /// Stable record ID derived from the persistent CG display UUID where available (it survives
    /// reboots and re-enumeration), falling back to the transient CG display ID. Scored identity
    /// resolution against persisted `DisplayRecord`s lands later (PRD D-009).
    private func recordID(uuid: String?, id: CGDirectDisplayID) -> DisplayRecordID {
        if let uuid { return DisplayRecordID(rawValue: "cg:\(uuid)") }
        return DisplayRecordID(rawValue: "cgid:\(id)")
    }

    /// Builds the identity fingerprint for a display from public Core Graphics EDID accessors
    /// (vendor/model/serial numbers + physical size). The registry scores this to recognize a
    /// display across reconnects. Nonisolated — pure CG reads, no actor state.
    public nonisolated func fingerprint(for cgID: CGDirectDisplayID) -> DisplayFingerprint {
        func valid(_ value: UInt32) -> Int? {
            (value == 0 || value == 0xFFFF_FFFF) ? nil : Int(value)
        }
        let serial = CGDisplaySerialNumber(cgID)
        let size = CGDisplayScreenSize(cgID) // millimeters; (0,0) when unknown
        return DisplayFingerprint(
            vendorID: valid(CGDisplayVendorNumber(cgID)),
            productID: valid(CGDisplayModelNumber(cgID)),
            serialNumber: serial == 0 ? nil : String(serial),
            physicalWidthMM: size.width > 0 ? Int(size.width.rounded()) : nil,
            physicalHeightMM: size.height > 0 ? Int(size.height.rounded()) : nil
        )
    }

    /// One display's target arrangement for `applyArrangement`.
    public struct ArrangementTarget: Sendable {
        public var displayID: CGDirectDisplayID
        public var origin: DisplayOrigin?
        public var mode: DisplayMode?
        public init(displayID: CGDirectDisplayID, origin: DisplayOrigin?, mode: DisplayMode?) {
            self.displayID = displayID
            self.origin = origin
            self.mode = mode
        }
    }

    /// Applies display positions and modes atomically inside one Core Graphics configuration
    /// transaction (`.permanently`). Restoring origins also restores the main display, since the
    /// display at (0,0) is the main one. Reversible — apply another arrangement to undo. Returns
    /// human-readable warnings for anything it couldn't satisfy (e.g. an unavailable mode).
    /// Nonisolated: pure CG calls, no actor state.
    public nonisolated func applyArrangement(_ targets: [ArrangementTarget]) -> [String] {
        var warnings: [String] = []
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            return ["could not begin display configuration"]
        }
        var changed = false
        for target in targets {
            // Mode first (resolution can shift the origin), then origin. Skip whatever already
            // matches so a no-op apply doesn't flicker the displays.
            if let mode = target.mode, !modeSatisfied(target.displayID, mode) {
                if let cgMode = bestMode(for: target.displayID, matching: mode) {
                    if CGConfigureDisplayWithDisplayMode(config, target.displayID, cgMode, nil) == .success {
                        changed = true
                    } else {
                        warnings.append("could not set mode for \(target.displayID)")
                    }
                } else {
                    warnings.append("no matching mode for \(target.displayID) (\(mode.pixelWidth)x\(mode.pixelHeight)@\(Int(mode.refreshHz.rounded())))")
                }
            }
            if let origin = target.origin {
                let current = CGDisplayBounds(target.displayID).origin
                if Int(current.x.rounded()) != origin.x || Int(current.y.rounded()) != origin.y {
                    if CGConfigureDisplayOrigin(config, target.displayID, Int32(origin.x), Int32(origin.y)) == .success {
                        changed = true
                    } else {
                        warnings.append("could not move \(target.displayID)")
                    }
                }
            }
        }
        guard changed else {
            CGCancelDisplayConfiguration(config)
            return warnings
        }
        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            warnings.append("apply failed (complete error)")
        }
        return warnings
    }

    private nonisolated func modeSatisfied(_ id: CGDirectDisplayID, _ desired: DisplayMode) -> Bool {
        guard let current = CGDisplayCopyDisplayMode(id) else { return false }
        // Compare the logical (point) size + HiDPI + refresh: a scaled HiDPI mode and a native mode
        // can share pixel dimensions, so a pixel-only check would wrongly treat them as identical.
        return current.width == desired.pointWidth && current.height == desired.pointHeight
            && (current.pixelWidth > current.width) == desired.isHiDPI
            && abs(current.refreshRate - desired.refreshHz) < 1
    }

    private nonisolated func bestMode(for id: CGDirectDisplayID, matching desired: DisplayMode) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return nil }
        // Prefer an exact logical (point) + HiDPI + refresh match, since a scaled HiDPI mode and a
        // native mode can share pixel dimensions; fall back to a pixel match if none lines up.
        return modes.first {
            $0.width == desired.pointWidth && $0.height == desired.pointHeight
                && ($0.pixelWidth > $0.width) == desired.isHiDPI
                && abs($0.refreshRate - desired.refreshHz) < 1
        } ?? modes.first {
            $0.pixelWidth == desired.pixelWidth && $0.pixelHeight == desired.pixelHeight
                && abs($0.refreshRate - desired.refreshHz) < 1
        }
    }

    /// Every display mode (un-deduped), including scaled-HiDPI and refresh-rate variants — drives the
    /// refresh-rate picker and HiDPI toggle, which need to see all modes at a given point-resolution.
    public nonisolated func allModes(for cgID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(cgID, options) as? [CGDisplayMode] else { return [] }
        return cgModes.map {
            DisplayMode(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                        pointWidth: $0.width, pointHeight: $0.height,
                        refreshHz: $0.refreshRate, isHiDPI: $0.pixelWidth > $0.width)
        }
    }

    /// All selectable resolutions for a display, de-duplicated to one mode per point-size (HiDPI
    /// preferred, then highest refresh) and sorted by area ascending — drives the resolution slider.
    public nonisolated func availableModes(for cgID: CGDirectDisplayID) -> [DisplayMode] {
        // Include scaled HiDPI ("looks like") modes — without this option the built-in returns only
        // its 1:1 pixel modes, so the user's actual scaled resolution wouldn't appear in the list.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(cgID, options) as? [CGDisplayMode] else { return [] }
        var best: [String: DisplayMode] = [:]
        for cg in cgModes {
            let mode = DisplayMode(
                pixelWidth: cg.pixelWidth, pixelHeight: cg.pixelHeight,
                pointWidth: cg.width, pointHeight: cg.height,
                refreshHz: cg.refreshRate, isHiDPI: cg.pixelWidth > cg.width)
            let key = "\(mode.pointWidth)x\(mode.pointHeight)"
            let rank = (mode.isHiDPI ? 1 : 0, mode.refreshHz)
            if let existing = best[key] {
                if rank > (existing.isHiDPI ? 1 : 0, existing.refreshHz) { best[key] = mode }
            } else {
                best[key] = mode
            }
        }
        return best.values.sorted { $0.pointWidth * $0.pointHeight < $1.pointWidth * $1.pointHeight }
    }

    private func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    private func displayMode(from mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            pointWidth: mode.width,
            pointHeight: mode.height,
            refreshHz: mode.refreshRate,
            isHiDPI: mode.pixelWidth > mode.width
        )
    }

    private func rotation(of id: CGDirectDisplayID) -> Rotation {
        switch Int(CGDisplayRotation(id).rounded()) {
        case 90: return .degrees90
        case 180: return .degrees180
        case 270: return .degrees270
        default: return .degrees0
        }
    }

    /// A compact fingerprint of the structural topology used to decide when to advance the
    /// generation: which displays are online, active, main, mirrored, where/how big they are, and
    /// their rotation + refresh rate. Rotation and refresh matter because they can change while
    /// bounds stay identical (180° flip, refresh-only mode switch) — omitting them left the
    /// generation stuck, so `awaitStableGeneration` sat out its full timeout after such a change.
    private func topologySignature(of ids: [CGDirectDisplayID]) -> String {
        ids.sorted().map { id in
            let b = CGDisplayBounds(id)
            let active = CGDisplayIsActive(id) != 0 ? 1 : 0
            let main = CGDisplayIsMain(id) != 0 ? 1 : 0
            let mirror = CGDisplayMirrorsDisplay(id)
            let rotation = Int(CGDisplayRotation(id).rounded())
            let refresh = Int(((CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0) * 10).rounded())
            return "\(id):\(active):\(main):\(Int(b.origin.x)),\(Int(b.origin.y)):"
                + "\(Int(b.size.width))x\(Int(b.size.height)):\(mirror):\(rotation):\(refresh)"
        }
        .joined(separator: "|")
    }
}
#endif
