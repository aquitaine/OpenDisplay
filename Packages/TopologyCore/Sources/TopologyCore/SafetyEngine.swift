import DisplayDomain
import Foundation

/// The non-bypassable preflight authority for destructive lifecycle actions. Automation cannot
/// route around it (PRD §10.3 SafetyEngine boundary). Pure and deterministic so it is fully
/// unit-testable against generated topologies.
public struct SafetyEngine: Sendable {
    public init() {}

    public enum Decision: Equatable, Sendable {
        /// Safe to proceed without extra confirmation.
        case allowed(safeSurface: DisplayRecordID)
        /// Allowed only behind a first-use / elevated-risk countdown confirmation (LIF-006).
        case needsConfirmation(safeSurface: DisplayRecordID, reasons: [Reason])
        /// Must not proceed on the default path (LIF-003, §9.2 invariants 3/4).
        case blocked(reasons: [Reason])

        public var isBlocked: Bool {
            if case .blocked = self { return true }
            return false
        }

        public var safeSurface: DisplayRecordID? {
            switch self {
            case .allowed(let surface), .needsConfirmation(let surface, _): return surface
            case .blocked: return nil
            }
        }
    }

    public enum Reason: String, Equatable, Sendable {
        case noSafeSurface
        case wouldRemoveLastSafeDisplay
        case identityBelowThreshold
        case targetIsCurrentMain
        case recoveryServiceUnhealthy
        case firstUseForRoute
        case ambiguousIdentity
    }

    /// Computes a safe surface: an active, non-mirrored display with a stable identity that is not
    /// in the disconnect target set and is not itself slated to disappear (PRD §9.6).
    public func safeSurface(in snapshot: TopologySnapshot,
                           excluding targets: Set<DisplayRecordID>) -> DisplayRecordID? {
        let candidates = snapshot.activeDisplays.filter { observation in
            !targets.contains(observation.recordID)
                && !observation.isMirrored
                && observation.overlayIsRecoverable
        }
        // Prefer the built-in panel, then the current main, then any stable candidate. Deterministic
        // ordering keeps preflight reproducible across runs.
        if let builtIn = candidates.first(where: { $0.displayClass == .builtIn }) {
            return builtIn.recordID
        }
        if let main = candidates.first(where: { $0.isMain }) {
            return main.recordID
        }
        return candidates.sorted { $0.recordID.rawValue < $1.recordID.rawValue }.first?.recordID
    }

    /// Preflight a single logical disconnect (PRD §9.4 "Preflight safety", §9.2 invariants).
    public func preflightDisconnect(
        target: DisplayRecordID,
        snapshot: TopologySnapshot,
        identityConfidence: Double,
        recoveryServiceHealthy: Bool,
        isFirstUseForRoute: Bool,
        confidenceThreshold: Double = IdentityConfidence.destructiveThreshold
    ) -> Decision {
        var blocking: [Reason] = []
        var confirmations: [Reason] = []

        guard recoveryServiceHealthy else {
            return .blocked(reasons: [.recoveryServiceUnhealthy])
        }

        // Invariant 3/§9.6: there must be a safe surface left after removing the target.
        guard let surface = safeSurface(in: snapshot, excluding: [target]) else {
            // Distinguish "removing the last safe display" from "no safe surface at all".
            let activeOthers = snapshot.activeDisplays.filter { $0.recordID != target }
            blocking.append(activeOthers.isEmpty ? .wouldRemoveLastSafeDisplay : .noSafeSurface)
            return .blocked(reasons: blocking)
        }

        // Invariant 4 (LIF-004): identity must clear the destructive threshold or be confirmed.
        if identityConfidence < confidenceThreshold {
            confirmations.append(.identityBelowThreshold)
        }

        // Disconnecting the current main requires moving the main/recovery role first (LIF-017,
        // §9.10): allowed, but always confirmed.
        if snapshot.observation(for: target)?.isMain == true {
            confirmations.append(.targetIsCurrentMain)
        }

        if isFirstUseForRoute {
            confirmations.append(.firstUseForRoute)
        }

        return confirmations.isEmpty
            ? .allowed(safeSurface: surface)
            : .needsConfirmation(safeSurface: surface, reasons: confirmations)
    }
}

private extension DisplayObservation {
    /// A blacked-out or filtered surface can't be relied on for recovery feedback unless the
    /// recovery path removes overlays (PRD §9.6). Treated conservatively here.
    var overlayIsRecoverable: Bool {
        overlay == .visible || overlay == .dimmed
    }
}
