import Foundation

/// Pure decision core for App Presets (Issue #33) — the "when this app comes to the front, switch the
/// monitor to a brightness/contrast/colour preset, and put it back when the app leaves" feature.
///
/// Deterministic and clock-free in the same shape as `AdaptiveDisplayPolicy` and `FaceLightPolicy`:
/// the caller injects `now` (used only for debounce arithmetic), threads a caller-owned
/// `ActivationState` through, and receives a `Decision` naming the writes to issue and how the restore
/// ledger should change. All hardware writes, NSWorkspace observation, persistence, and UI belong to
/// the caller (`AppModel`) — this type only decides.
///
/// Restore ledger (`ActivationState.priorStateByDisplay`, mirrored to
/// `OpenDisplaySettings.appPresetPriorStateByDisplay`): a display's real pre-preset values, owed back
/// when its preset stops applying. Captured BEFORE the preset write lands and cleared only after a
/// confirmed restore — the same persist-before-write / clear-after-restore invariant FaceLight's
/// prior-state ledger and Adaptive Display's day-preset ledger use, so a crash or relaunch mid-preset
/// still recovers the display's true state instead of stranding it at a preset value. ::
///
///     resolve(frontmost "com.figma", presets: [figma→60% on all], activeBundleID: nil)
///     ok: captures the live brightness, applyWrites 60%, appPresetIsActive: true
///
///     resolve(frontmost "com.apple.Finder", activeBundleID "com.figma")   // Figma left the front
///     ok: restoreWrites the captured brightness, clears the ledger, appPresetIsActive: false
///
/// Last-writer precedence (documented and unit-tested): an app preset is a debounced, app-driven
/// switch that outranks Adaptive Display's built-in mirror, the ambient curve, and Clock Mode on the
/// displays it governs — the caller pauses those on `appPresetIsActive` displays. FaceLight, an
/// explicit hotkey, outranks app presets: the caller excludes FaceLight-active displays from `Input`,
/// so this policy never targets one.
public enum AppPresetPolicy {
    /// Which displays an app preset governs.
    public enum Target: Hashable, Sendable, Codable {
        /// Every active external display.
        case allDisplays
        /// One specific display, by `DisplayRecordID.rawValue`.
        case display(String)
    }

    /// One configured app preset (settings): "when `bundleIdentifier` is frontmost, drive `target`'s
    /// displays to these values". Each field is optional so a preset can set only brightness, or add
    /// contrast and/or a colour preset. `applicationName` is a display label for the settings list.
    public struct AppPreset: Hashable, Sendable, Codable, Identifiable {
        public var id: UUID
        public var bundleIdentifier: String
        public var applicationName: String
        public var brightness: Float?
        public var contrast: Float?
        public var colorPreset: Int?
        public var target: Target

        public init(id: UUID = UUID(), bundleIdentifier: String, applicationName: String,
                    brightness: Float? = nil, contrast: Float? = nil, colorPreset: Int? = nil,
                    target: Target = .allDisplays) {
            self.id = id
            self.bundleIdentifier = bundleIdentifier
            self.applicationName = applicationName
            self.brightness = brightness
            self.contrast = contrast
            self.colorPreset = colorPreset
            self.target = target
        }

        /// Whether this preset drives any hardware channel at all (an empty preset is a no-op).
        public var hasAnyWrite: Bool {
            brightness != nil || contrast != nil || colorPreset != nil
        }
    }

    /// A display's pre-preset values, owed back when its preset stops applying. Only the fields the
    /// preset actually writes are recorded — an unset field means "this preset never touched it, so
    /// there is nothing to restore". Mirrors `FaceLightPolicy.PriorState`.
    public struct PriorState: Hashable, Sendable, Codable {
        public var brightness: Float?
        public var contrast: Float?
        public var colorPreset: Int?

        public init(brightness: Float? = nil, contrast: Float? = nil, colorPreset: Int? = nil) {
            self.brightness = brightness
            self.contrast = contrast
            self.colorPreset = colorPreset
        }
    }

    /// One active external display's live values, read fresh by the caller so an activation captures
    /// what is really on screen right now rather than a stale cache.
    public struct DisplaySnapshot: Hashable, Sendable {
        public var recordID: String
        public var brightness: Float?
        public var contrast: Float?
        public var colorPreset: Int?

        public init(recordID: String, brightness: Float? = nil, contrast: Float? = nil,
                    colorPreset: Int? = nil) {
            self.recordID = recordID
            self.brightness = brightness
            self.contrast = contrast
            self.colorPreset = colorPreset
        }
    }

    /// Caller-owned state threaded through `resolve`. `activeBundleID` is the app whose preset is
    /// currently applied (nil = displays at their own baseline); `pendingBundleID`/`pendingSince` hold
    /// a not-yet-committed switch during the debounce window; `priorStateByDisplay` is the restore
    /// ledger keyed by `DisplayRecordID.rawValue`.
    public struct ActivationState: Hashable, Sendable {
        public var activeBundleID: String?
        public var pendingBundleID: String?
        public var pendingSince: Date?
        public var priorStateByDisplay: [String: PriorState]

        public init(activeBundleID: String? = nil, pendingBundleID: String? = nil,
                    pendingSince: Date? = nil, priorStateByDisplay: [String: PriorState] = [:]) {
            self.activeBundleID = activeBundleID
            self.pendingBundleID = pendingBundleID
            self.pendingSince = pendingSince
            self.priorStateByDisplay = priorStateByDisplay
        }
    }

    /// One evaluation's worth of observed world, assembled by the caller. `displays` excludes any
    /// FaceLight-active display (FaceLight outranks app presets), so this policy never targets one.
    public struct Input: Sendable {
        public var frontmostBundleID: String?
        public var now: Date
        public var presets: [AppPreset]
        public var displays: [DisplaySnapshot]
        public var debounce: TimeInterval

        public init(frontmostBundleID: String?, now: Date, presets: [AppPreset],
                    displays: [DisplaySnapshot], debounce: TimeInterval = AppPresetPolicy.defaultDebounce) {
            self.frontmostBundleID = frontmostBundleID
            self.now = now
            self.presets = presets
            self.displays = displays
            self.debounce = debounce
        }
    }

    /// A single display's write, with only the channels the preset (or restore) touches populated.
    public struct DisplayWrite: Hashable, Sendable {
        public var recordID: String
        public var brightness: Float?
        public var contrast: Float?
        public var colorPreset: Int?

        public init(recordID: String, brightness: Float? = nil, contrast: Float? = nil,
                    colorPreset: Int? = nil) {
            self.recordID = recordID
            self.brightness = brightness
            self.contrast = contrast
            self.colorPreset = colorPreset
        }
    }

    /// What the caller should do this evaluation. Apply in THIS order to hold the restore-owed
    /// invariant across a crash: persist every `captures` entry into the ledger FIRST (before the
    /// preset write makes a restore owed), issue `applyWrites`, issue `restoreWrites`, then persist the
    /// `clears` removals (only after those restores land). Finally store `state`. `appPresetIsActive`
    /// drives the Adaptive/Clock pause on the governed displays; `rescheduleAfter`, when non-nil, asks
    /// the caller to re-run `resolve` after that delay (the debounce window is still open).
    public struct Decision: Hashable, Sendable {
        public var captures: [String: PriorState]
        public var applyWrites: [DisplayWrite]
        public var restoreWrites: [DisplayWrite]
        public var clears: [String]
        public var state: ActivationState
        public var appPresetIsActive: Bool
        public var rescheduleAfter: TimeInterval?

        public init(captures: [String: PriorState] = [:], applyWrites: [DisplayWrite] = [],
                    restoreWrites: [DisplayWrite] = [], clears: [String] = [],
                    state: ActivationState, appPresetIsActive: Bool,
                    rescheduleAfter: TimeInterval? = nil) {
            self.captures = captures
            self.applyWrites = applyWrites
            self.restoreWrites = restoreWrites
            self.clears = clears
            self.state = state
            self.appPresetIsActive = appPresetIsActive
            self.rescheduleAfter = rescheduleAfter
        }
    }

    /// Debounce window for a frontmost-app switch. Rapid app cycling (Cmd-Tab spam, a launcher briefly
    /// stealing focus) shouldn't fire a DDC write per hop — 0.4s lets the front settle first while
    /// still feeling immediate when the user lands on an app.
    public static let defaultDebounce: TimeInterval = 0.4

    /// Decide what the current frontmost app means for the governed displays. See `Decision` for the
    /// order the caller must apply the result in.
    public static func resolve(_ input: Input, state: ActivationState) -> Decision {
        let desiredBundleID = desiredBundle(frontmost: input.frontmostBundleID, presets: input.presets)
        if desiredBundleID == state.activeBundleID {
            return steadyDecision(state: withoutPending(state))
        }
        return debounce(desiredBundleID: desiredBundleID, input: input, state: state)
    }

    // MARK: - Debounce

    private static func debounce(desiredBundleID: String?, input: Input,
                                 state: ActivationState) -> Decision {
        var working = state
        // `pendingSince` distinguishes an open window from none, so a deactivation (desired == nil)
        // debounces like any other switch instead of reading as "already pending nil".
        let windowOpen = working.pendingSince != nil && working.pendingBundleID == desiredBundleID
        guard windowOpen else {
            working.pendingBundleID = desiredBundleID
            working.pendingSince = input.now
            return pendingDecision(state: working, reschedule: input.debounce)
        }
        let elapsed = input.now.timeIntervalSince(working.pendingSince ?? input.now)
        guard elapsed >= input.debounce else {
            return pendingDecision(state: working, reschedule: max(0, input.debounce - elapsed))
        }
        return commit(desiredBundleID: desiredBundleID, input: input, state: working)
    }

    private static func steadyDecision(state: ActivationState) -> Decision {
        Decision(state: state, appPresetIsActive: state.activeBundleID != nil)
    }

    private static func pendingDecision(state: ActivationState, reschedule: TimeInterval) -> Decision {
        Decision(state: state, appPresetIsActive: state.activeBundleID != nil,
                 rescheduleAfter: reschedule)
    }

    // MARK: - Commit

    private static func commit(desiredBundleID: String?, input: Input,
                               state: ActivationState) -> Decision {
        let incoming = desiredBundleID.flatMap { preset(for: $0, in: input.presets) }
        let targetIDs = incoming.map { targetDisplayIDs($0, displays: input.displays) } ?? []
        let targetSet = Set(targetIDs)
        var ledger = state.priorStateByDisplay

        let restore = restoreDisplaysLeaving(targetSet: targetSet, ledger: &ledger)
        let application = applyIncoming(incoming, targetIDs: targetIDs, displays: input.displays,
                                        ledger: &ledger)

        var finalState = withoutPending(state)
        finalState.activeBundleID = desiredBundleID
        finalState.priorStateByDisplay = ledger
        return Decision(captures: application.captures, applyWrites: application.writes,
                        restoreWrites: restore.writes, clears: restore.clears, state: finalState,
                        appPresetIsActive: desiredBundleID != nil)
    }

    /// Restore every owed display that the incoming preset no longer governs, dropping its ledger
    /// entry — the restore write must land before the entry clears (see `Decision`).
    private static func restoreDisplaysLeaving(targetSet: Set<String>,
                                               ledger: inout [String: PriorState])
        -> (writes: [DisplayWrite], clears: [String]) {
        var writes: [DisplayWrite] = []
        var clears: [String] = []
        for recordID in ledger.keys.sorted() where !targetSet.contains(recordID) {
            guard let prior = ledger[recordID] else { continue }
            writes.append(restoreWrite(recordID: recordID, prior: prior))
            clears.append(recordID)
            ledger[recordID] = nil
        }
        return (writes, clears)
    }

    /// Capture a baseline for each newly governed display (keeping any baseline already owed from a
    /// prior app, so switching apps never records a preset value as the real baseline) and write the
    /// incoming preset's values.
    private static func applyIncoming(_ incoming: AppPreset?, targetIDs: [String],
                                      displays: [DisplaySnapshot], ledger: inout [String: PriorState])
        -> (captures: [String: PriorState], writes: [DisplayWrite]) {
        guard let incoming else { return ([:], []) }
        var captures: [String: PriorState] = [:]
        var writes: [DisplayWrite] = []
        for recordID in targetIDs {
            if ledger[recordID] == nil {
                let prior = capturePrior(preset: incoming, snapshot: snapshot(recordID, in: displays))
                captures[recordID] = prior
                ledger[recordID] = prior
            }
            writes.append(applyWrite(recordID: recordID, preset: incoming))
        }
        return (captures, writes)
    }

    // MARK: - Resolution helpers

    /// The bundle id whose preset should govern the front: the frontmost app when it has a usable
    /// preset configured, otherwise nil (no app preset should be active → restore to baseline).
    private static func desiredBundle(frontmost: String?, presets: [AppPreset]) -> String? {
        guard let frontmost, let match = preset(for: frontmost, in: presets), match.hasAnyWrite else {
            return nil
        }
        return frontmost
    }

    private static func preset(for bundleID: String, in presets: [AppPreset]) -> AppPreset? {
        presets.first { $0.bundleIdentifier == bundleID }
    }

    private static func targetDisplayIDs(_ preset: AppPreset,
                                         displays: [DisplaySnapshot]) -> [String] {
        switch preset.target {
        case .allDisplays:
            return displays.map(\.recordID)
        case .display(let recordID):
            return displays.contains { $0.recordID == recordID } ? [recordID] : []
        }
    }

    private static func capturePrior(preset: AppPreset, snapshot: DisplaySnapshot?) -> PriorState {
        PriorState(brightness: preset.brightness != nil ? snapshot?.brightness : nil,
                   contrast: preset.contrast != nil ? snapshot?.contrast : nil,
                   colorPreset: preset.colorPreset != nil ? snapshot?.colorPreset : nil)
    }

    private static func applyWrite(recordID: String, preset: AppPreset) -> DisplayWrite {
        DisplayWrite(recordID: recordID, brightness: preset.brightness, contrast: preset.contrast,
                     colorPreset: preset.colorPreset)
    }

    private static func restoreWrite(recordID: String, prior: PriorState) -> DisplayWrite {
        DisplayWrite(recordID: recordID, brightness: prior.brightness, contrast: prior.contrast,
                     colorPreset: prior.colorPreset)
    }

    private static func snapshot(_ recordID: String, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        displays.first { $0.recordID == recordID }
    }

    private static func withoutPending(_ state: ActivationState) -> ActivationState {
        var updated = state
        updated.pendingBundleID = nil
        updated.pendingSince = nil
        return updated
    }
}
