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
/// noticed promptly. It performs no mutation; logical connect/disconnect lives in a separate
/// (experimental) `LifecycleProvider`, and only documented Apple APIs are used here so this
/// provider stays in the public-API-only build (NFR-010, D-008).
public actor CoreGraphicsProvider: TopologyObserving, DisplayProvider {
    public nonisolated let providerID = "coregraphics.v1"
    public nonisolated let isExperimental = false

    private var generation: TopologyGeneration = .initial
    private var lastSignature = ""

    public init() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(openDisplayReconfigurationCallback, opaque)
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            openDisplayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
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

    // MARK: Reconfiguration event source

    /// Invoked off the CG reconfiguration callback. Recomputing the topology bumps the generation
    /// if the signature changed; redundant callbacks (e.g. the begin-configuration phase) are
    /// harmless no-ops because the signature is unchanged.
    func handleReconfiguration(rawFlags: UInt32) {
        _ = currentTopology()
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
    /// generation: which displays are online, active, main, mirrored, and where/how big they are.
    private func topologySignature(of ids: [CGDirectDisplayID]) -> String {
        ids.sorted().map { id in
            let b = CGDisplayBounds(id)
            let active = CGDisplayIsActive(id) != 0 ? 1 : 0
            let main = CGDisplayIsMain(id) != 0 ? 1 : 0
            let mirror = CGDisplayMirrorsDisplay(id)
            return "\(id):\(active):\(main):\(Int(b.origin.x)),\(Int(b.origin.y)):"
                + "\(Int(b.size.width))x\(Int(b.size.height)):\(mirror)"
        }
        .joined(separator: "|")
    }
}
#endif
