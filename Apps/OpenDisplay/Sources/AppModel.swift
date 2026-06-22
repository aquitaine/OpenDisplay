#if os(macOS)
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import ProviderInterfaces
import TopologyCore

/// The app's composition root. It wires the platform-independent `TopologyCoordinator`
/// (Packages/TopologyCore) to a display system and exposes an observable snapshot for the UI.
///
/// M0: observation now comes from the real `CoreGraphicsProvider` (live display enumeration +
/// a reconfiguration event source). The lifecycle path (logical disconnect/reconnect) is not a
/// Core Graphics capability — it arrives with the `ExperimentalLifecycleProvider`, wired behind
/// `#if !PUBLIC_API_ONLY`. Until then a provider that honestly reports the lifecycle as
/// unavailable backs the coordinator, so nothing pretends to mutate real hardware.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayObservation] = []
    @Published private(set) var statusText = "Scanning…"
    @Published private(set) var busy = false

    private let observer: CoreGraphicsProvider
    private let coordinator: TopologyCoordinator

    init() {
        let observer = CoreGraphicsProvider()
        self.observer = observer
        self.coordinator = TopologyCoordinator(
            observer: observer,
            lifecycleProvider: UnavailableLifecycleProvider(),
            checkpoints: InMemoryCheckpointStore()
        )
        Task { await refresh() }
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
    /// managed-offline displays yet, this is a safe no-op until the lifecycle provider lands.
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
}

/// Stands in for a `LifecycleProvider` until the real ones are wired (M0 step 3). Reports the
/// lifecycle path as unavailable rather than pretending to succeed (verify-not-assume, D-010).
private struct UnavailableLifecycleProvider: LifecycleProvider {
    let providerID = "lifecycle.unavailable"
    let isExperimental = false

    func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        ProviderProbe(providerID: providerID, status: .unsupported, risk: .normal, reasons: [.buildFlavor])
    }

    func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }

    func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }

    func recover(to checkpoint: Checkpoint) async throws {
        throw ProviderFailure.unsupported(reason: [.buildFlavor])
    }
}
#endif
