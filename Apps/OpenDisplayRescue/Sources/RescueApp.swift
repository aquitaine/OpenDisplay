#if os(macOS)
import DisplayDomain
import Foundation
import SimulatorProvider
import SwiftUI
import TopologyCore

/// The independent rescue utility (PRD LIF-011, DIA-010, D-004). It reconnects managed-offline
/// displays and (in M0) restores checkpoints and disables auto-apply policies — usable even when
/// the main app is unavailable. Minimal-dependency by design.
@main
struct OpenDisplayRescueApp: App {
    var body: some Scene {
        WindowGroup("OpenDisplay Rescue") {
            RescueView()
        }
        .defaultSize(width: 460, height: 300)
    }
}

@MainActor
final class RescueModel: ObservableObject {
    @Published private(set) var log = "Ready. This runs independently of the main app."

    private let system: SimulatedDisplaySystem
    private let coordinator: TopologyCoordinator

    init() {
        let system = SimulatedDisplaySystem(
            observations: [
                DisplayObservation(recordID: .init(rawValue: "disp_builtin"), isActive: true,
                                   isMain: true, displayClass: .builtIn, generation: .initial),
                DisplayObservation(recordID: .init(rawValue: "disp_lg"), isActive: false,
                                   displayClass: .external, generation: .initial)
            ],
            managedOffline: [
                ManagedOfflineRecord(displayID: .init(rawValue: "disp_lg"), actor: .recovery,
                                     reason: "rescue demo", providerID: "simulator.lifecycle.v1")
            ]
        )
        self.system = system
        self.coordinator = TopologyCoordinator(
            observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore()
        )
    }

    func reconnectAll() async {
        let results = await coordinator.reconnectAll()
        let restored = results.filter { $0.value }.count
        log = "Reconnect All: \(restored)/\(results.count) restored."
    }
}

struct RescueView: View {
    @StateObject private var model = RescueModel()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Recovering your displays").font(.title3)
            Text(model.log).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reconnect All") { Task { await model.reconnectAll() } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
