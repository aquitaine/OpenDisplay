import DisplayDomain
import Foundation

/// A single planned change produced by diffing a scene's desired state against the observed
/// topology. Used both for the dry-run/diff preview (TOP-011, AUT-11) and for actual application.
public struct PlannedOperation: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case reconnect
        case disconnect
        case setMain
        case setPosition
        case setMode
        case setRotation
        case setBrightness
        case setColorProfile
        case setHDR
        case createMirror
    }

    /// Whether this op will run, is already satisfied (skipped for idempotency), or can't apply.
    public enum Status: String, Hashable, Sendable, Codable {
        case willApply
        case alreadySatisfied
        case unsupported
        case experimental
        case hardwareDependent
    }

    public var kind: Kind
    public var target: DisplayRecordID
    public var detail: String
    public var status: Status
    public var risk: RiskLevel

    public init(kind: Kind, target: DisplayRecordID, detail: String, status: Status, risk: RiskLevel = .normal) {
        self.kind = kind
        self.target = target
        self.detail = detail
        self.status = status
        self.risk = risk
    }
}

/// The full dry-run plan for applying a scene.
public struct ScenePlan: Hashable, Sendable, Codable {
    public var sceneID: String
    public var generation: TopologyGeneration
    public var operations: [PlannedOperation]
    public var missingRequired: [String]
    public var missingOptional: [String]

    public init(
        sceneID: String,
        generation: TopologyGeneration,
        operations: [PlannedOperation],
        missingRequired: [String] = [],
        missingOptional: [String] = []
    ) {
        self.sceneID = sceneID
        self.generation = generation
        self.operations = operations
        self.missingRequired = missingRequired
        self.missingOptional = missingOptional
    }

    /// A required member could not be resolved → application must be blocked (TOP-014).
    public var isBlocked: Bool { !missingRequired.isEmpty }

    /// Idempotency check: a fully-satisfied scene produces no actionable operations (TOP-013).
    public var hasWork: Bool { operations.contains { $0.status == .willApply } }
}

/// Pure, deterministic scene planner. Given resolved member→record mappings and an observed
/// snapshot, it produces an ordered, idempotent plan. Ordering follows PRD §10.7: connect
/// destinations → main/position/mode/rotation → controls → disconnect retiring displays last.
public struct ScenePlanner: Sendable {
    public init() {}

    /// Resolution of each member selector to a concrete record (or `nil` if unresolved/absent).
    public typealias Resolution = [String: DisplayRecordID]

    public func plan(scene: Scene, snapshot: TopologySnapshot, resolution: Resolution) -> ScenePlan {
        var operations: [PlannedOperation] = []
        var missingRequired: [String] = []
        var missingOptional: [String] = []

        // Stable member order keeps the plan deterministic regardless of input ordering.
        let orderedMembers = scene.members.sorted { $0.selector < $1.selector }

        for member in orderedMembers {
            guard let recordID = resolution[member.selector] else {
                if member.required { missingRequired.append(member.selector) }
                else { missingOptional.append(member.selector) }
                continue
            }
            let observed = snapshot.observation(for: recordID)
            operations.append(contentsOf: plannedOperations(for: member.desired, target: recordID, observed: observed))
        }

        operations = ordered(operations)
        return ScenePlan(
            sceneID: scene.id,
            generation: snapshot.generation,
            operations: operations,
            missingRequired: missingRequired,
            missingOptional: missingOptional
        )
    }

    private func plannedOperations(for desired: DesiredState,
                                   target: DisplayRecordID,
                                   observed: DisplayObservation?) -> [PlannedOperation] {
        var ops: [PlannedOperation] = []

        if let connected = desired.connected {
            let isActive = observed?.isActive ?? false
            if connected && !isActive {
                ops.append(.init(kind: .reconnect, target: target, detail: "Reconnect display",
                                 status: .willApply, risk: .recoveryCritical))
            } else if !connected && isActive {
                ops.append(.init(kind: .disconnect, target: target, detail: "Logically disconnect",
                                 status: .willApply, risk: .recoveryCritical))
            } else {
                ops.append(.init(kind: connected ? .reconnect : .disconnect, target: target,
                                 detail: connected ? "Already connected" : "Already offline",
                                 status: .alreadySatisfied,
                                 risk: .recoveryCritical))
            }
        }

        if let main = desired.main, main {
            let isMain = observed?.isMain ?? false
            ops.append(.init(kind: .setMain, target: target,
                             detail: "Use as main display",
                             status: isMain ? .alreadySatisfied : .willApply))
        }

        if let position = desired.position {
            let satisfied = observed?.origin == position
            ops.append(.init(kind: .setPosition, target: target,
                             detail: "Move to (\(position.x), \(position.y))",
                             status: satisfied ? .alreadySatisfied : .willApply))
        }

        if let mode = desired.mode {
            let satisfied = observed?.mode == mode
            ops.append(.init(kind: .setMode, target: target,
                             detail: "\(mode.pointWidth) × \(mode.pointHeight) @ \(Int(mode.refreshHz)) Hz",
                             status: satisfied ? .alreadySatisfied : .willApply))
        }

        if let rotation = desired.rotation {
            let satisfied = observed?.rotation == rotation
            ops.append(.init(kind: .setRotation, target: target,
                             detail: "Rotate \(rotation.rawValue)°",
                             status: satisfied ? .alreadySatisfied : .willApply))
        }

        if let brightness = desired.brightness {
            ops.append(.init(kind: .setBrightness, target: target,
                             detail: "Brightness \(Int(brightness))%",
                             status: .willApply, risk: .hardwareDependent))
        }

        if let profile = desired.colorProfile {
            let satisfied = observed?.colorProfileName == profile
            ops.append(.init(kind: .setColorProfile, target: target,
                             detail: "Color profile “\(profile)”",
                             status: satisfied ? .alreadySatisfied : .willApply))
        }

        if let hdr = desired.hdr {
            let satisfied = observed?.hdrEnabled == hdr
            ops.append(.init(kind: .setHDR, target: target,
                             detail: hdr ? "Enable HDR" : "Disable HDR",
                             status: satisfied ? .alreadySatisfied : .willApply,
                             risk: hdr ? .experimental : .normal))
        }

        return ops
    }

    /// Safe operation ordering (PRD §10.7, TOP-012): reconnects first, then layout/mode/controls,
    /// and disconnects strictly last so a safe surface is always established before any removal.
    private func ordered(_ ops: [PlannedOperation]) -> [PlannedOperation] {
        func rank(_ kind: PlannedOperation.Kind) -> Int {
            switch kind {
            case .reconnect: return 0
            case .createMirror: return 1
            case .setMain: return 2
            case .setPosition: return 3
            case .setMode: return 4
            case .setRotation: return 5
            case .setColorProfile: return 6
            case .setHDR: return 7
            case .setBrightness: return 8
            case .disconnect: return 9
            }
        }
        return ops.enumerated()
            .sorted { lhs, rhs in
                let lr = rank(lhs.element.kind), rr = rank(rhs.element.kind)
                return lr == rr ? lhs.offset < rhs.offset : lr < rr
            }
            .map(\.element)
    }
}
