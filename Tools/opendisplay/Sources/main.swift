import DisplayDomain
import Foundation
import SimulatorProvider
import TopologyCore

// Minimal CLI scaffold (PRD §12). It demonstrates the automation path running through the same
// core the UI uses. The full grammar (list/get/set/scene/connect/disconnect/recover/diagnose),
// stable selectors, JSON output, and dry-run — built on ArgumentParser — land in M1.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "list"

let system = SimulatedDisplaySystem(
    observations: [
        DisplayObservation(recordID: .init(rawValue: "disp_builtin"), isActive: true,
                           isMain: true, displayClass: .builtIn, generation: .initial),
        DisplayObservation(recordID: .init(rawValue: "disp_studio"), isActive: true,
                           displayClass: .external, generation: .initial),
        DisplayObservation(recordID: .init(rawValue: "disp_lg"), isActive: false,
                           displayClass: .external, generation: .initial)
    ],
    managedOffline: [
        ManagedOfflineRecord(displayID: .init(rawValue: "disp_lg"), actor: .cli,
                             reason: "cli demo", providerID: "simulator.lifecycle.v1")
    ]
)
let coordinator = TopologyCoordinator(
    observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore()
)

switch command {
case "list":
    let snapshot = await system.currentSnapshot()
    for display in snapshot.observations.sorted(by: { $0.recordID.rawValue < $1.recordID.rawValue }) {
        let mark = display.isActive ? "●" : "○"
        let role = display.isMain ? " (main)" : ""
        print("\(mark) \(display.recordID.rawValue)\(role)")
    }
case "recover":
    let results = await coordinator.reconnectAll()
    for (id, ok) in results.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("\(ok ? "reconnected" : "failed   ") \(id.rawValue)")
    }
default:
    print("usage: opendisplay [list|recover]")
}
