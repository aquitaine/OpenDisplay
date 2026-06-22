import DisplayDomain
import Foundation

/// Captures the live arrangement into a `Scene` and resolves a scene's member selectors back to
/// records for planning (PRD §13.2). Pure + deterministic, so it is covered by `make test`.
public enum SceneRecorder {
    /// Snapshots the current arrangement as a scene: one member per observed display, selected by
    /// its stable record id, asserting the current connected / main / position / mode / rotation.
    /// Members are optional so a later apply skips (rather than blocks on) a now-absent display.
    public static func capture(from snapshot: TopologySnapshot, name: String, id: String) -> Scene {
        let members = snapshot.observations
            .sorted { $0.recordID.rawValue < $1.recordID.rawValue }
            .map { observation in
                Scene.Member(
                    selector: "id:\(observation.recordID.rawValue)",
                    required: false,
                    desired: DesiredState(
                        connected: observation.isActive,
                        main: observation.isMain ? true : nil,
                        position: observation.origin,
                        mode: observation.mode,
                        rotation: observation.rotation
                    )
                )
            }
        return Scene(id: id, name: name, members: members)
    }

    /// Resolves `id:`/`main`/`builtin` member selectors against a snapshot. Registry-backed
    /// selectors (`alias:`/`tag:`) are resolved by the caller that owns the registry (the CLI/app),
    /// which can pass a richer resolution into `ScenePlanner`.
    public static func resolution(for scene: Scene, in snapshot: TopologySnapshot) -> ScenePlanner.Resolution {
        var resolution: ScenePlanner.Resolution = [:]
        for member in scene.members {
            let selector = member.selector
            if selector.hasPrefix("id:") {
                let recordID = DisplayRecordID(rawValue: String(selector.dropFirst("id:".count)))
                if snapshot.observation(for: recordID) != nil { resolution[selector] = recordID }
            } else if selector == "main" {
                if let observation = snapshot.observations.first(where: { $0.isMain }) {
                    resolution[selector] = observation.recordID
                }
            } else if selector == "builtin" {
                if let observation = snapshot.observations.first(where: { $0.displayClass == .builtIn }) {
                    resolution[selector] = observation.recordID
                }
            }
        }
        return resolution
    }
}
