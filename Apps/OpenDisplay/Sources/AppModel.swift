#if os(macOS)
import DisplayDomain
import Foundation
import SimulatorProvider
import TopologyCore

/// The app's composition root. It wires the platform-independent `TopologyCoordinator`
/// (Packages/TopologyCore) to a display system and exposes an observable snapshot for the UI.
///
/// Today it uses `SimulatedDisplaySystem` so the menu-bar UI runs before the real macOS
/// providers exist. M0 swaps in `CoreGraphicsProvider` (observation) and, behind
/// `#if !PUBLIC_API_ONLY`, the `ExperimentalLifecycleProvider`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayObservation] = []
    @Published private(set) var statusText = "Scanning…"
    @Published private(set) var busy = false

    private let system: SimulatedDisplaySystem
    private let coordinator: TopologyCoordinator

    init() {
        let system = SimulatedDisplaySystem(
            observations: AppModel.demoDisplays(),
            managedOffline: [
                ManagedOfflineRecord(displayID: .init(rawValue: "disp_lg"), actor: .ui,
                                     reason: "demo", providerID: "simulator.lifecycle.v1")
            ]
        )
        self.system = system
        self.coordinator = TopologyCoordinator(
            observer: system,
            lifecycleProvider: system,
            checkpoints: InMemoryCheckpointStore()
        )
        Task { await refresh() }
    }

    func refresh() async {
        let snapshot = await system.currentSnapshot()
        displays = snapshot.observations.sorted { $0.recordID.rawValue < $1.recordID.rawValue }
        statusText = "\(snapshot.activeDisplays.count) active · \(snapshot.observations.count) total"
    }

    /// Emergency recovery — always available (PRD LIF-010).
    func reconnectAll() async {
        busy = true
        defer { busy = false }
        _ = await coordinator.reconnectAll()
        await refresh()
    }

    /// Demo topology (built-in + studio active, an LG managed-offline) so the UI renders before
    /// real providers exist. Replaced by live enumeration in M0.
    static func demoDisplays() -> [DisplayObservation] {
        [
            DisplayObservation(recordID: .init(rawValue: "disp_builtin"), isActive: true,
                               isMain: true, displayClass: .builtIn, generation: .initial),
            DisplayObservation(recordID: .init(rawValue: "disp_studio"), isActive: true,
                               displayClass: .external, generation: .initial),
            DisplayObservation(recordID: .init(rawValue: "disp_lg"), isActive: false,
                               displayClass: .external, generation: .initial)
        ]
    }
}
#endif
