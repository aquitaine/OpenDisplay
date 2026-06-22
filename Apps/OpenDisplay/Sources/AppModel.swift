#if os(macOS)
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import ProviderInterfaces
import TopologyCore
#if !PUBLIC_API_ONLY
import ExperimentalLifecycleProvider
#endif

/// The app's composition root. It wires the platform-independent `TopologyCoordinator`
/// (Packages/TopologyCore) to a display system and exposes an observable snapshot for the UI.
///
/// M0: observation comes from the real `CoreGraphicsProvider` (live enumeration + a
/// reconfiguration event source). The lifecycle path prefers the experimental SkyLight provider
/// (true logical disconnect, full build only) and falls back to `CoreGraphicsProvider`'s public,
/// reversible mirroring approach — selected by `RoutedLifecycleProvider`. In the public-API-only
/// build the experimental module is absent and the public provider is used directly.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayObservation] = []
    @Published private(set) var statusText = "Scanning…"
    @Published private(set) var busy = false

    private let observer: CoreGraphicsProvider
    private let coordinator: TopologyCoordinator
    private let checkpoints: any CheckpointStoring
    private let lifecycle: any LifecycleProvider

    init() {
        let observer = CoreGraphicsProvider()
        self.observer = observer
        let checkpoints = AppModel.makeCheckpointStore()
        self.checkpoints = checkpoints
        let lifecycle = AppModel.makeLifecycleProvider(public: observer)
        self.lifecycle = lifecycle
        self.coordinator = TopologyCoordinator(
            observer: observer,
            lifecycleProvider: lifecycle,
            checkpoints: checkpoints
        )
        Task {
            await refresh()
            await writeBaselineCheckpoint()
            #if DEBUG
            if let token = ProcessInfo.processInfo.environment["OPENDISPLAY_DISCONNECT"] {
                await debugDisconnectCycle(token: token)
            }
            #endif
        }
    }

    /// Builds the lifecycle provider: experimental-primary + public-fallback in the full build,
    /// the public provider alone in the public-API-only build.
    private static func makeLifecycleProvider(public publicProvider: CoreGraphicsProvider) -> any LifecycleProvider {
        #if PUBLIC_API_ONLY
        return publicProvider
        #else
        return RoutedLifecycleProvider(primary: ExperimentalLifecycleProvider(), fallback: publicProvider)
        #endif
    }

    /// Persistent, rescue-readable checkpoints in Application Support, falling back to in-memory
    /// only if that directory can't be resolved.
    private static func makeCheckpointStore() -> any CheckpointStoring {
        if let directory = try? DiskCheckpointStore.defaultDirectory() {
            return DiskCheckpointStore(directory: directory)
        }
        return InMemoryCheckpointStore()
    }

    /// Records the current arrangement as a last-known-safe baseline so the rescue utility has
    /// something to restore even before any disconnect runs (PRD §9.4).
    private func writeBaselineCheckpoint() async {
        let snapshot = await observer.currentSnapshot()
        let checkpoint = Checkpoint(
            transactionID: TransactionID(rawValue: "txn_baseline"),
            generation: snapshot.generation,
            observations: snapshot.observations,
            mainDisplayID: snapshot.observations.first(where: { $0.isMain })?.recordID,
            managedOffline: snapshot.managedOffline
        )
        try? await checkpoints.writeAtomic(checkpoint)
    }

    func refresh() async {
        let snapshot = await observer.currentSnapshot()
        displays = snapshot.observations.sorted { $0.recordID.rawValue < $1.recordID.rawValue }
        statusText = "\(snapshot.activeDisplays.count) active · \(snapshot.observations.count) total"
        if ProcessInfo.processInfo.environment["OPENDISPLAY_DUMP"] != nil {
            Self.dump(snapshot)
        }
    }

    /// Emergency recovery — always available (PRD LIF-010). With live observation and no
    /// managed-offline displays yet, this is a safe no-op until a disconnect path is exercised.
    func reconnectAll() async {
        busy = true
        defer { busy = false }
        _ = await coordinator.reconnectAll()
        await refresh()
    }

    /// Diagnostic dump of the observed topology to stderr, gated on `OPENDISPLAY_DUMP` so it is
    /// silent in normal runs. Run the app binary directly with the env var set to verify live
    /// enumeration without needing the menu-bar UI.
    private static func dump(_ snapshot: TopologySnapshot) {
        var out = "OpenDisplay topology \(snapshot.generation):\n"
        for o in snapshot.observations.sorted(by: { $0.recordID.rawValue < $1.recordID.rawValue }) {
            let mode = o.mode.map { "\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshHz.rounded()))" } ?? "—"
            out += "  \(o.isActive ? "●" : "○") \(o.recordID.rawValue)"
            out += " cgID=\(o.cgDisplayID ?? 0)\(o.isMain ? " [main]" : "")"
            out += " \(o.displayClass.rawValue) \(mode) origin=(\(o.origin.x),\(o.origin.y))"
            out += o.isMirrored ? " mirrors=\(o.mirrorSourceID?.rawValue ?? "")" : ""
            out += "\n"
        }
        FileHandle.standardError.write(Data(out.utf8))
    }

    #if DEBUG
    /// M0 live-test harness (DEBUG only, gated on `OPENDISPLAY_DISCONNECT=<cgID|recordID>`): runs
    /// one real disconnect through the full coordinator transaction, logs the result + stage path
    /// to stderr, then **always reconnects after 3s** so a live test can never strand a display.
    /// Never target the main display — the coordinator blocks removing the last safe surface.
    private func debugDisconnectCycle(token: String) async {
        let snapshot = await observer.currentSnapshot()
        guard let observation = snapshot.observations.first(where: {
            $0.cgDisplayID.map(String.init) == token || $0.recordID.rawValue == token
        }) else {
            Self.err("DISCONNECT: no display matches \(token)")
            return
        }
        let target = observation.recordID
        // Reconnect by raw display ID so restore can't fail on UUID resolution after the display
        // drops off the online list while logically disabled.
        let reconnectID = observation.cgDisplayID.map { DisplayRecordID(rawValue: "cgid:\($0)") } ?? target

        Self.err("DISCONNECT target \(target.rawValue) (cgID \(observation.cgDisplayID ?? 0)) — running coordinator transaction…")
        do {
            let result = try await coordinator.disconnect(
                target, options: DisconnectOptions(actor: .cli, identityConfidence: 1.0)
            )
            let stages = await coordinator.lastTransition.map { "\($0)" }.joined(separator: " → ")
            Self.err("DISCONNECT result: \(result)\n  stages: \(stages)")
        } catch {
            Self.err("DISCONNECT error: \(error)")
        }
        // Proof of mechanism: with the private disable, the target drops out of the online list
        // (or is inactive with NO mirror source). The public mirror fallback would instead leave it
        // online with mirrorSourceID set. Captured during the offline window, before reconnect.
        let post = await observer.currentSnapshot()
        let summary = post.observations
            .map { "\($0.recordID.rawValue) active=\($0.isActive) mirror=\($0.mirrorSourceID?.rawValue ?? "none")" }
            .joined(separator: " | ")
        Self.err("POST-DISCONNECT online=\(post.observations.count): \(summary)")
        // Restore unconditionally so the test is self-healing.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        do {
            try await lifecycle.reconnect(reconnectID, deadline: Date().addingTimeInterval(10))
            Self.err("RECONNECT \(reconnectID.rawValue): done")
        } catch {
            Self.err("RECONNECT \(reconnectID.rawValue) error: \(error)")
        }
        await refresh()
    }

    private static func err(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
    #endif
}

/// Prefers a primary lifecycle provider and falls back to a public one only when the primary
/// reports the operation `.unsupported` (e.g. the private SkyLight symbols are absent on this OS).
/// Other failures propagate — a real OS rejection must not silently retry by another mechanism.
private struct RoutedLifecycleProvider: LifecycleProvider {
    let primary: any LifecycleProvider
    let fallback: any LifecycleProvider

    let providerID = "routed.lifecycle.v1"
    var isExperimental: Bool { primary.isExperimental }

    func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        let probe = await primary.probe(environment)
        return probe.status == .supported ? probe : await fallback.probe(environment)
    }

    func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try await active().disconnect(target, deadline: deadline)
    }

    func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try await active().reconnect(target, deadline: deadline)
    }

    func recover(to checkpoint: Checkpoint) async throws {
        try await active().recover(to: checkpoint)
    }

    /// Pick the provider by probe status — a forward capability check, so an unsupported primary
    /// never even attempts the operation. (`catch as ProviderFailure` is now also boundary-safe: the
    /// shared core ships as dynamic frameworks — see project.yml — so `ProviderFailure` has exactly
    /// one runtime type across all images. Error-based fallback would work too; probe-based routing is
    /// kept because deciding up front beats reacting to a thrown failure.)
    private func active() async -> any LifecycleProvider {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let environment = ProviderEnvironment(
            osBuild: "", isAppleSilicon: appleSilicon, transport: .unknown, displayClass: .unknown
        )
        return await primary.probe(environment).status == .supported ? primary : fallback
    }
}
#endif
