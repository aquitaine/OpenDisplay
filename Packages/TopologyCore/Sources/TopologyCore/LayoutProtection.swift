import DisplayDomain
import Foundation
import SceneEngine

/// What a layout-protection command does to the current display set's stored arrangement.
public enum LayoutProtectionChange: String, Hashable, Sendable, Codable {
    case protect
    case unprotect
}

/// Pure decision core for Protected Layout (Batch-4 #A): the user marks one arrangement as the one
/// they want kept, and every topology event afterwards is measured against it.
///
/// Detection itself is the existing `DisplayConfigDrifter`. What this type adds is everything that
/// keeps an automatic restore from turning into a war with the machine: which drifts are worth
/// restoring, which are the user's own standing intent (the managed-offline ledger), and the three
/// anti-fight guards — self-change suppression, a stability debounce, and a per-generation retry cap.
///
/// Deterministic and clock-free: the caller injects `now`, threads a caller-owned `State` through,
/// and gets back a `Decision` naming what to do. Every hardware, persistence, and UI side effect
/// belongs to the caller (AppModel / the CLI), so `make test` covers the whole decision table.
public enum LayoutProtectionPolicy {
    /// Why the caller is asking. Recorded in the audit trail, and `wake`/`launch` clear the
    /// per-generation retry budget: the same generation before and after a sleep is a different
    /// world (displays come back in their own order), so attempts spent before it shouldn't count.
    public enum Trigger: String, Hashable, Sendable, Codable {
        case topologyChange
        case wake
        case launch
    }

    /// Why an evaluation deliberately did nothing. Each is a guard, not a failure.
    public enum IgnoreReason: String, Hashable, Sendable, Codable {
        /// The master toggle is off.
        case protectionDisabled
        /// This generation is OpenDisplay's own doing — see `noteSelfChange`.
        case selfChange
        /// The topology hasn't been quiet long enough to be trusted yet.
        case debouncing
        /// Two restores already failed against this generation; giving up beats looping.
        case retryCapReached
    }

    public enum Decision: Hashable, Sendable {
        /// No protected layout exists for the current display set.
        case noMatch
        /// The live arrangement still matches the protected one.
        case clean
        /// The arrangement drifted in ways worth putting back; carries only the actionable changes.
        case restore(DisplayConfigDrifter.DriftAnalysis)
        case ignore(IgnoreReason)
    }

    /// Caller-owned state threaded through `decide` (mirrors `AdaptiveDisplayPolicy.DisplayState`).
    /// Session-only: none of it is worth persisting, and a relaunch starts from a clean baseline.
    public struct State: Hashable, Sendable {
        /// The generation the counters below belong to; a new generation resets them.
        public var generation: TopologyGeneration?
        /// When that generation was first seen — the debounce anchor.
        public var generationFirstSeenAt: Date?
        /// A generation raised by OpenDisplay's own write, which must never trigger a restore.
        public var suppressedGeneration: TopologyGeneration?
        /// Restores already issued against `generation`.
        public var restoreAttempts: Int
        /// The give-up notification has been posted for `generation` (post it once, not per event).
        public var hasNotifiedFailure: Bool

        public init(generation: TopologyGeneration? = nil, generationFirstSeenAt: Date? = nil,
                    suppressedGeneration: TopologyGeneration? = nil, restoreAttempts: Int = 0,
                    hasNotifiedFailure: Bool = false) {
            self.generation = generation
            self.generationFirstSeenAt = generationFirstSeenAt
            self.suppressedGeneration = suppressedGeneration
            self.restoreAttempts = restoreAttempts
            self.hasNotifiedFailure = hasNotifiedFailure
        }
    }

    /// The observed world for one evaluation, assembled by the caller.
    public struct Context: Hashable, Sendable {
        public var now: Date
        /// The master toggle (`OpenDisplaySettings.layoutProtectionEnabled`).
        public var isEnabled: Bool
        /// Displays macOS reports as ASLEEP. Sleep is a power state, not a topology change — see
        /// `awake(_:context:)` for why reading it wrong would restore layouts at 3am.
        public var asleepDisplayIDs: Set<DisplayRecordID>
        /// Displays the user deliberately turned off (the `ManagedOfflineStore` ledger). Protection
        /// never fights this list.
        public var managedOfflineIDs: Set<DisplayRecordID>
        /// Seconds of topology quiet required before drift is trusted.
        public var debounce: TimeInterval
        /// Restores allowed per stable generation before giving up.
        public var maximumRestoreAttempts: Int

        public init(now: Date, isEnabled: Bool,
                    asleepDisplayIDs: Set<DisplayRecordID> = [],
                    managedOfflineIDs: Set<DisplayRecordID> = [],
                    debounce: TimeInterval = LayoutProtectionPolicy.defaultDebounce,
                    maximumRestoreAttempts: Int = LayoutProtectionPolicy.defaultMaximumRestoreAttempts) {
            self.now = now
            self.isEnabled = isEnabled
            self.asleepDisplayIDs = asleepDisplayIDs
            self.managedOfflineIDs = managedOfflineIDs
            self.debounce = debounce
            self.maximumRestoreAttempts = maximumRestoreAttempts
        }
    }

    /// One evaluation's outcome. Apply in THIS order: post the failure notification when
    /// `shouldNotifyFailure`, arm a re-check after `recheckAfter`, act on `decision` (calling
    /// `noteRestoreAttempt` when you issue the restore), then store `state`.
    public struct Evaluation: Hashable, Sendable {
        public var decision: Decision
        public var state: State
        /// The retry cap was reached *just now* — tell the user once, never once per event.
        public var shouldNotifyFailure: Bool
        /// The debounce window is still open; ask again after this many seconds.
        public var recheckAfter: TimeInterval?

        public init(decision: Decision, state: State, shouldNotifyFailure: Bool = false,
                    recheckAfter: TimeInterval? = nil) {
            self.decision = decision
            self.state = state
            self.shouldNotifyFailure = shouldNotifyFailure
            self.recheckAfter = recheckAfter
        }
    }

    /// Seconds of quiet before drift is trusted. A hotplug or a wake emits a burst of
    /// reconfiguration events with half-formed arrangements in between; restoring against one of
    /// those fights macOS while it is still settling. Same instinct as `awaitStableGeneration`:
    /// wait for the world to hold still, then look.
    public static let defaultDebounce: TimeInterval = 3

    /// Restores allowed per stable generation. macOS can refuse an arrangement outright (a mode the
    /// panel no longer offers, a display mid-negotiation) and retrying forever would be an infinite
    /// loop against it — two tries, then say so and stop.
    public static let defaultMaximumRestoreAttempts = 2

    /// The scene id every protected-layout restore runs under, so the audit trail names it.
    public static let restoreSceneID = "layout_protection_restore"

    // MARK: - Display-set fingerprint

    /// The key a protected layout is stored under: the sorted member record ids of a display set.
    /// Keying on the set (rather than one global "the layout") is what lets "laptop alone" and
    /// "laptop + Desk" both be protected, each with its own arrangement, without overwriting.
    public static func fingerprint(for recordIDs: some Sequence<DisplayRecordID>) -> String {
        Set(recordIDs).map(\.rawValue).sorted().joined(separator: "|")
    }

    /// The current display set's key: the displays on the desk, whether or not one of them is
    /// currently switched off.
    ///
    /// The ledger has to be part of it. "Turned the built-in off" is not a different desk — but a
    /// logically disabled display is absent from `CGGetOnlineDisplayList` entirely, so keying on the
    /// enumeration alone means the key silently changes the moment macOS relights that display. That
    /// is exactly what happens on wake, and it made protection a guaranteed no-op at the one moment
    /// it was most needed: the arrangement was filed under "two externals" and the machine woke up
    /// asking about "two externals and a built-in".
    ///
    /// macOS's synthetic placeholder is excluded deliberately (0.8.2): it appears when every real
    /// display has gone, and letting it into the key would mint a phantom display set — and protect it.
    public static func fingerprint(for snapshot: TopologySnapshot,
                                   managedOffline: Set<DisplayRecordID>) -> String {
        fingerprint(for: members(of: snapshot, managedOffline: managedOffline))
    }

    /// The displays that make up this set, in the fingerprint's own sorted order.
    public static func members(of snapshot: TopologySnapshot,
                               managedOffline: Set<DisplayRecordID> = []) -> [DisplayRecordID] {
        Set(realDisplays(of: snapshot).map(\.recordID)).union(managedOffline)
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// The displays a stored arrangement covers, including the ones it says must stay off — what the
    /// Settings row and `layout status` count and name.
    public static func members(of config: ProtectedConfig) -> [DisplayRecordID] {
        members(of: config.snapshot, managedOffline: desiredOff(in: config.snapshot))
    }

    /// The protected layout for this display set, if the user has protected it.
    public static func protectedLayout(for snapshot: TopologySnapshot,
                                       managedOffline: Set<DisplayRecordID>,
                                       in layouts: [String: ProtectedConfig]) -> ProtectedConfig? {
        layouts[fingerprint(for: snapshot, managedOffline: managedOffline)]
    }

    /// Captures the live arrangement as the protected layout for its own display set. Re-protecting
    /// overwrites, because the key is derived from the members rather than minted.
    ///
    /// The ledger is captured with it, in the snapshot's own `managedOffline` field. Without that the
    /// stored arrangement has no way to say "and this display is off" — a logically disabled display
    /// leaves no trace in the enumeration to record — so a restore could put everything else back
    /// perfectly and still leave the built-in lit.
    public static func capture(_ snapshot: TopologySnapshot,
                               managedOffline: [ManagedOfflineDisplay] = [],
                               at now: Date) -> (fingerprint: String, config: ProtectedConfig) {
        let switchedOff = switchedOffIDs(in: snapshot, ledger: managedOffline)
        let alreadyRecorded = snapshot.managedOffline
        let owed = alreadyRecorded + switchedOff
            .subtracting(alreadyRecorded.map(\.displayID))
            .sorted { $0.rawValue < $1.rawValue }
            .map {
                ManagedOfflineRecord(displayID: $0, actor: .ui, reason: "protected layout",
                                     disconnectedAt: now, providerID: "")
            }
        let real = TopologySnapshot(
            generation: snapshot.generation, observations: realDisplays(of: snapshot),
            managedOffline: owed, capturedAt: snapshot.capturedAt)
        return (fingerprint(for: real, managedOffline: switchedOff),
                ProtectedConfig(snapshot: real, capturedAt: now))
    }

    /// Every display on this desk that is switched off right now: the caller's ledger, plus anything
    /// the snapshot itself already records as offline.
    ///
    /// Both sources are merged rather than one winning, and every caller that keys or captures a
    /// layout goes through here. The app's ledger is the live record — Core Graphics snapshots carry
    /// no offline list at all — while an observer that does report one (the simulator, a checkpoint
    /// replay) knows things the caller may not. Two callers deriving this two ways is precisely how
    /// `protect` and the lookup that follows it end up disagreeing about which desk they are on.
    public static func switchedOffIDs(in snapshot: TopologySnapshot,
                                      ledger: [ManagedOfflineDisplay]) -> Set<DisplayRecordID> {
        Set(snapshot.managedOffline.map(\.displayID)).union(ledger.map(\.recordID))
    }

    /// The displays a protected arrangement says must be OFF — the ledger it was captured with, plus
    /// any member that was captured dark.
    ///
    /// Both halves are needed because "off" has two shapes. The experimental provider truly disables
    /// a display, so it is absent from the capture and survives only in the ledger; the public
    /// provider MIRRORS it onto main, so it is captured, present, and inactive. One arrangement,
    /// recorded two ways, and a restore has to recognise it either way.
    public static func desiredOff(in protected: TopologySnapshot) -> Set<DisplayRecordID> {
        Set(protected.managedOffline.map(\.displayID))
            .union(protected.observations.filter { !$0.isActive }.map(\.recordID))
    }

    private static func realDisplays(of snapshot: TopologySnapshot) -> [DisplayObservation] {
        snapshot.observations.filter { $0.displayClass != .virtual }
    }

    // MARK: - Decision

    /// The whole decision: is this display set protected, has it drifted in a way worth acting on,
    /// and is any of the anti-fight machinery holding us back?
    public static func decide(current: TopologySnapshot,
                              protected: ProtectedConfig?,
                              trigger: Trigger,
                              context: Context,
                              state: State) -> Evaluation {
        var state = state
        if state.generation != current.generation {
            state.generation = current.generation
            state.generationFirstSeenAt = context.now
            state.restoreAttempts = 0
            state.hasNotifiedFailure = false
        }
        if trigger != .topologyChange {
            // A wake (or a relaunch) is a fresh start even when the generation number is unchanged:
            // the attempts before it were spent against a machine that was, in every way that
            // matters, elsewhere.
            state.restoreAttempts = 0
            state.hasNotifiedFailure = false
        }

        guard context.isEnabled else {
            return Evaluation(decision: .ignore(.protectionDisabled), state: state)
        }
        guard let protected else { return Evaluation(decision: .noMatch, state: state) }
        guard state.suppressedGeneration != current.generation else {
            return Evaluation(decision: .ignore(.selfChange), state: state)
        }
        let quietFor = context.now.timeIntervalSince(state.generationFirstSeenAt ?? context.now)
        guard quietFor >= context.debounce else {
            return Evaluation(decision: .ignore(.debouncing), state: state,
                              recheckAfter: context.debounce - quietFor)
        }
        guard let analysis = actionableDrift(protected: protected.snapshot, current: current,
                                             context: context) else {
            return Evaluation(decision: .noMatch, state: state)
        }
        guard analysis.hasDrifted else { return Evaluation(decision: .clean, state: state) }
        guard state.restoreAttempts < context.maximumRestoreAttempts else {
            let shouldNotify = !state.hasNotifiedFailure
            state.hasNotifiedFailure = true
            return Evaluation(decision: .ignore(.retryCapReached), state: state,
                              shouldNotifyFailure: shouldNotify)
        }
        return Evaluation(decision: .restore(analysis), state: state)
    }

    /// The drift worth acting on, or nil when the current display set is not the protected set.
    ///
    /// Two rules do the filtering, and both turn on the same distinction.
    ///
    /// A display that appeared or disconnected normally means a *different* set is on the desk, and
    /// that set's own protected layout (if any) is the one that applies —
    /// restoring this one would drag a departed display's geometry onto the displays actually
    /// present. The exception is a display the protected arrangement says must be OFF: the
    /// experimental provider's "off" removes it from the enumeration entirely, so it *appears* the
    /// moment macOS relights it and *disconnects* the moment we put it away. Neither is a new desk;
    /// one is the drift to fix and the other is that fix having landed.
    ///
    /// The ledger rule is directional, and that direction is the whole point. A change to a display
    /// the user turned off is left alone only when the protected arrangement wants that display ON —
    /// there the ledger is the newer instruction and protection must not fight it. When the
    /// protected arrangement wants it off too, restoring and the ledger agree, so the change IS
    /// actionable. Read undirected (as it first shipped) the rule reads "never touch a display the
    /// user turned off", which sounds right and means the app watches macOS switch the built-in back
    /// on at every wake and decides, on principle, to leave it that way.
    ///
    /// Both rules cover `mirrorChanged` as well as the obvious `activeChanged`, because
    /// "turned off" has two shapes. The public lifecycle provider has no API to truly remove a
    /// display, so it approximates the disconnect by MIRRORING the display onto main — the only
    /// path in the public-API-only build, and the fallback in the full one. A display turned off
    /// that way is still enumerated, still in the protected set, and differs from the protected
    /// snapshot in exactly one field: its mirror source. Un-mirroring it because the protected
    /// snapshot has it lit would put back the display the user turned off — and, worse, the app
    /// would then see it "come back on its own" and drop its ledger entry, which is the only record
    /// that it is owed a reconnect at all.
    public static func actionableDrift(protected: TopologySnapshot,
                                       current: TopologySnapshot,
                                       context: Context) -> DisplayConfigDrifter.DriftAnalysis? {
        let analysis = DisplayConfigDrifter.detectDrift(protected: protected,
                                                       current: awake(current, context: context))
        let wantsOff = desiredOff(in: protected)
        var actionable: [DisplayConfigDrifter.Change] = []
        for change in analysis.changes {
            switch change {
            case .appeared(let displayID):
                guard wantsOff.contains(displayID) else { return nil }
                actionable.append(change)
            case .disconnected(let displayID):
                // The arrangement asked for this display to be gone and it is — or the user has
                // since turned it off themselves. Either way this is convergence, not a new desk.
                guard wantsOff.contains(displayID) || context.managedOfflineIDs.contains(displayID)
                else { return nil }
            case .activeChanged(let displayID), .mirrorChanged(let displayID):
                if !context.managedOfflineIDs.contains(displayID) || wantsOff.contains(displayID) {
                    actionable.append(change)
                }
            case .originMoved, .modeChanged, .rotationChanged, .mainChanged:
                actionable.append(change)
            }
        }
        return DisplayConfigDrifter.DriftAnalysis(changes: actionable)
    }

    /// The snapshot as the always-one-active safety net sees it: a merely SLEEPING display is a
    /// present, usable surface, not one that went away (0.8.2). Drift evaluation has to use the same
    /// predicate — read raw activity instead and every idle screen looks like a display the user
    /// turned off, so protection would wake the Mac up restoring it in the middle of the night.
    private static func awake(_ snapshot: TopologySnapshot, context: Context) -> TopologySnapshot {
        guard !context.asleepDisplayIDs.isEmpty else { return snapshot }
        let observations = snapshot.observations.map { observation -> DisplayObservation in
            guard context.asleepDisplayIDs.contains(observation.recordID) else { return observation }
            var surface = observation
            surface.isActive = DisplayActivity.isActiveSurface(cgIsActive: observation.isActive,
                                                               cgIsAsleep: true)
            return surface
        }
        return TopologySnapshot(generation: snapshot.generation, observations: observations,
                                managedOffline: snapshot.managedOffline,
                                capturedAt: snapshot.capturedAt)
    }

    // MARK: - State transitions

    /// Marks a generation as OpenDisplay's own doing — a scene apply, a protected-layout restore, or
    /// an arrangement change the user made *through the app*.
    ///
    /// Call it with the generation observed AFTER the write lands (`awaitStableGeneration`), because
    /// that is the generation our own write raises: suppressing it is what stops a restore loop
    /// feeding on itself, and it is why the app never undoes a change the user just asked it for.
    public static func noteSelfChange(generation: TopologyGeneration, state: State) -> State {
        var state = state
        state.suppressedGeneration = generation
        return state
    }

    /// Records that a restore was just issued, spending one of this generation's attempts.
    public static func noteRestoreAttempt(state: State) -> State {
        var state = state
        state.restoreAttempts += 1
        return state
    }

    /// Records what a restore's own writes actually did to the world: suppress the generation they
    /// raised, or — when they raised none, which means the restore did not land — clear the
    /// suppression entirely.
    ///
    /// That second half matters more than it looks. Marking the unchanged generation as "ours" would
    /// silence the very drift we just failed to fix, and the retry cap would never be reached: the
    /// layout would sit broken with the app quietly certain it had already handled it.
    public static func noteRestoreOutcome(before: TopologyGeneration, after: TopologyGeneration,
                                          state: State) -> State {
        var state = state
        state.suppressedGeneration = after > before ? after : nil
        return state
    }

    // MARK: - Restore plan

    /// The one-shot scene that puts the protected arrangement back. Members are optional so a
    /// display that stepped out mid-restore is skipped rather than blocking the apply, and the
    /// desired state is exactly what was captured. This rides the app's existing `applyScene` path,
    /// so checkpointing, verification, the audit trail, and the always-one-active net all apply
    /// without a second lifecycle implementation to keep in step.
    ///
    /// Displays the arrangement wants OFF are left out. Their captured geometry is not a place on
    /// the desk — a display mirrored onto main was captured sitting exactly where main sits — so
    /// asserting it would move a display that is supposed to be dark, and moving a mirrored display
    /// is one of the ways macOS decides to un-mirror it.
    public static func restoreScene(for config: ProtectedConfig) -> Scene {
        let wantsOff = desiredOff(in: config.snapshot)
        let lit = TopologySnapshot(
            generation: config.snapshot.generation,
            observations: config.snapshot.observations.filter { !wantsOff.contains($0.recordID) },
            managedOffline: config.snapshot.managedOffline,
            capturedAt: config.snapshot.capturedAt)
        return SceneRecorder.capture(from: lit, name: "Protected layout", id: restoreSceneID)
    }

    // MARK: - User-facing copy

    /// A human summary of what drifted, for the restore notification: per display, the fields that
    /// moved, plus the main-display change when it happened.
    public static func summary(of analysis: DisplayConfigDrifter.DriftAnalysis,
                               names: [DisplayRecordID: String]) -> String {
        var fieldsByDisplay: [DisplayRecordID: [String]] = [:]
        var mainMoved = false
        for change in analysis.changes {
            switch change {
            case .originMoved(let displayID): fieldsByDisplay[displayID, default: []].append("position")
            case .modeChanged(let displayID): fieldsByDisplay[displayID, default: []].append("resolution")
            case .rotationChanged(let displayID): fieldsByDisplay[displayID, default: []].append("rotation")
            case .mirrorChanged(let displayID): fieldsByDisplay[displayID, default: []].append("mirroring")
            // `appeared` reaches here only for a display the arrangement wants off — macOS switched
            // it back on and the restore switched it away again, which reads as "on/off" like any
            // other activity change.
            case .activeChanged(let displayID), .appeared(let displayID):
                fieldsByDisplay[displayID, default: []].append("on/off")
            case .mainChanged: mainMoved = true
            case .disconnected: break
            }
        }
        var parts = fieldsByDisplay
            .map { (name: names[$0.key] ?? $0.key.rawValue, fields: $0.value) }
            .sorted { $0.name < $1.name }
            .map { "\($0.name): \($0.fields.joined(separator: ", "))" }
        if mainMoved { parts.append("main display") }
        return parts.joined(separator: " · ")
    }

    /// The notification for a completed auto-restore, or nil when notifications are off.
    public static func restoreNotification(for analysis: DisplayConfigDrifter.DriftAnalysis,
                                           names: [DisplayRecordID: String],
                                           enabled: Bool) -> NotificationPolicy.DisplayNotification? {
        guard enabled, analysis.hasDrifted else { return nil }
        return NotificationPolicy.DisplayNotification(
            title: "Restored your protected layout", body: summary(of: analysis, names: names))
    }

    /// The notification for giving up after the retry cap, or nil when notifications are off. Says
    /// what to do next, because silently leaving protection off would be the worse failure.
    public static func failureNotification(enabled: Bool) -> NotificationPolicy.DisplayNotification? {
        guard enabled else { return nil }
        return NotificationPolicy.DisplayNotification(
            title: "Couldn\u{2019}t restore your protected layout",
            body: "macOS kept the arrangement it had. Protect the current layout again to accept it.")
    }
}
