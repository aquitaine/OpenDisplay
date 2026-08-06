import DisplayDomain
import Foundation

/// What must be lit right now, and which of the user's standing "turn this one off" decisions still
/// stand — the two halves of converging on the arrangement the user asked for after a wake.
///
/// They live in one policy because they answer one question from two sides. Waking a Mac is the one
/// moment when the display list lies in both directions at once: an external still re-negotiating
/// its link reads exactly like an external unplugged during sleep, and a built-in panel macOS lights
/// on its own reads exactly like one the user re-enabled by hand. Read either wrongly and the app
/// does the opposite of what was asked — it panics, lights the built-in the user turned off, and
/// then forgets an "off" was ever owed, so nothing puts it back.
///
/// The lifecycle precedence ladder these implement (the order the app applies them in, and the
/// lifecycle counterpart of the brightness ladder in `GroupSyncPolicy`):
///
///   1. **Always one active surface.** Nothing outranks it and nothing here trades it away. What
///      changes is only *when* it fires: a display plainly on its way back is given its few seconds
///      before the net concludes the user is stranded, and the net's own deadline guarantees the
///      0.8.2 black screen can never come back.
///   2. **The managed-offline ledger.** A display the user turned off through OpenDisplay. Its
///      "off" is re-asserted across a wake, because macOS relighting it is the OS's doing rather
///      than the user's. Rule 1 may light such a display as an emergency screen; this rule is what
///      puts it back once a real screen returns.
///   3. **Protected Layout** (`LayoutProtectionPolicy`) — the whole arrangement, opt-in.
///   4. **macOS's own restoration** — whatever the window server decides on wake. Everything above
///      outranks it, and anything it changed is drift.
///
/// Deterministic and clock-free: the caller injects `now` and the observed world and gets back a
/// decision, so `make test` covers the whole table without a machine that sleeps.
public enum WakeConvergencePolicy {
    /// Seconds after a wake during which a display's return is attributed to macOS rather than to
    /// the user. Displays come back in their own order and their own time — DisplayPort link
    /// training after a wake is routinely several seconds — so the window has to outlast the
    /// slowest panel while staying short enough that a user re-enabling a display a minute later is
    /// unambiguously their own decision.
    public static let defaultWakeWindow: TimeInterval = 20

    /// The longest the always-one-active net will wait for a display that looks like it is coming
    /// back before it lights the fallback anyway. This is the number that keeps rule 1 absolute: no
    /// matter what the display list claims, a dark Mac gets a screen back within this many seconds.
    public static let defaultRecoveryDeadline: TimeInterval = 8

    /// How long the safety net waits between looks while a display is still coming back. Short, and
    /// deliberately so: someone is looking at a dark screen for the duration, and a display lighting
    /// up normally raises a topology event that answers sooner anyway. The step never overshoots the
    /// deadline — `surfaceDecision` clamps the last wait to whatever is left of it.
    public static let defaultRecheckStep: TimeInterval = 0.5

    /// How long the ledger re-assert waits between looks. Longer, because nobody is staring at
    /// anything while it waits and it is purely a backstop: a display becoming active changes the
    /// topology signature, so the event stream is what normally ends this wait. Each pass costs a
    /// full topology re-read, and the window it covers is twenty seconds wide.
    public static let defaultReassertRecheckStep: TimeInterval = 2

    /// Times the app will put one display back off per wake before letting it be. Same instinct as
    /// `LayoutProtectionPolicy.defaultMaximumRestoreAttempts`: macOS can insist, and a tug-of-war
    /// the user watches flicker is worse than a display that stayed on.
    public static let defaultMaximumReassertAttempts = 2

    /// The observed world for one decision, assembled by the caller.
    public struct Context: Hashable, Sendable {
        public var now: Date
        /// Every display macOS enumerates right now, exactly as the app holds them.
        public var observations: [DisplayObservation]
        /// The managed-offline ledger in the app's own order (oldest entry first).
        public var managedOffline: [ManagedOfflineDisplay]
        /// When the machine last woke, or nil when it hasn't since launch.
        public var lastWakeAt: Date?
        /// True from `NSWorkspace.willSleepNotification` until the matching `didWakeNotification`.
        ///
        /// The pair is needed because the display list moves on both sides of it and the
        /// notification is not first in the queue: displays go dark as the machine goes down, and
        /// come back — raising reconfiguration events the app processes — before macOS gets round to
        /// saying the machine woke. Judged by `lastWakeAt` alone, those early events land outside
        /// every window and are read as the user's own doing, which is the same wrong answer this
        /// policy exists to stop, arrived at a few hundred milliseconds sooner.
        public var isBetweenSleepAndWake: Bool
        /// When the app first saw zero visible surfaces in the current dark spell, nil while it can
        /// see one. The caller owns this edge because only it knows when it last looked.
        public var darkSince: Date?
        /// Re-assert attempts already spent per display in this wake.
        public var reassertAttempts: [DisplayRecordID: Int]
        public var wakeWindow: TimeInterval
        public var recoveryDeadline: TimeInterval
        public var recheckStep: TimeInterval
        public var reassertRecheckStep: TimeInterval
        public var maximumReassertAttempts: Int

        public init(now: Date,
                    observations: [DisplayObservation],
                    managedOffline: [ManagedOfflineDisplay] = [],
                    lastWakeAt: Date? = nil,
                    isBetweenSleepAndWake: Bool = false,
                    darkSince: Date? = nil,
                    reassertAttempts: [DisplayRecordID: Int] = [:],
                    wakeWindow: TimeInterval = WakeConvergencePolicy.defaultWakeWindow,
                    recoveryDeadline: TimeInterval = WakeConvergencePolicy.defaultRecoveryDeadline,
                    recheckStep: TimeInterval = WakeConvergencePolicy.defaultRecheckStep,
                    reassertRecheckStep: TimeInterval =
                        WakeConvergencePolicy.defaultReassertRecheckStep,
                    maximumReassertAttempts: Int =
                        WakeConvergencePolicy.defaultMaximumReassertAttempts) {
            self.now = now
            self.observations = observations
            self.managedOffline = managedOffline
            self.lastWakeAt = lastWakeAt
            self.isBetweenSleepAndWake = isBetweenSleepAndWake
            self.darkSince = darkSince
            self.reassertAttempts = reassertAttempts
            self.wakeWindow = wakeWindow
            self.recoveryDeadline = recoveryDeadline
            self.recheckStep = recheckStep
            self.reassertRecheckStep = reassertRecheckStep
            self.maximumReassertAttempts = maximumReassertAttempts
        }
    }

    // MARK: - Rule 1: always one active surface

    /// What the always-one-active safety net should do about the surfaces it can see.
    public enum SurfaceDecision: Hashable, Sendable {
        /// At least one display the user can actually see is lit. Nothing to do.
        case satisfied
        /// Nothing is lit, but a display is plainly on its way back — look again in this many
        /// seconds rather than lighting a display the user turned off.
        case waitForWakingDisplay(TimeInterval)
        /// Nothing is lit and nothing is coming. Bring this display back, now.
        case restore(ManagedOfflineDisplay)
        /// Nothing is lit and the ledger has nothing left to bring back.
        case stranded
    }

    /// The displays the user can actually SEE right now.
    ///
    /// Two exclusions, both paid for in 0.8.2. macOS answers the loss of every real display by
    /// synthesising a `.virtual` placeholder rather than reporting zero, so counting it would mean
    /// the net never fires. And `isActive` must be the *surface* reading that counts a merely
    /// sleeping panel as present (`DisplayActivity.isActiveSurface`), never a raw `CGDisplayIsActive`
    /// — otherwise every idle Mac looks display-less.
    public static func visibleSurfaces(in observations: [DisplayObservation]) -> [DisplayObservation] {
        observations.filter { $0.isActive && $0.displayClass != .virtual }
    }

    /// The whole net decision: is anything lit, is anything coming, and what is there to fall back
    /// on if neither.
    public static func surfaceDecision(_ context: Context) -> SurfaceDecision {
        guard visibleSurfaces(in: context.observations).isEmpty else { return .satisfied }
        guard let fallback = fallbackSurface(in: context.managedOffline) else { return .stranded }
        let darkFor = context.now.timeIntervalSince(context.darkSince ?? context.now)
        let remaining = context.recoveryDeadline - darkFor
        guard remaining > 0, isDisplayOnItsWayBack(context) else { return .restore(fallback) }
        return .waitForWakingDisplay(min(context.recheckStep, remaining))
    }

    /// The display to light when nothing else will: the built-in first (it is attached to the
    /// machine and always answers), otherwise the most recently turned-off display.
    public static func fallbackSurface(
        in managedOffline: [ManagedOfflineDisplay]
    ) -> ManagedOfflineDisplay? {
        managedOffline.first { $0.displayClass == .builtIn } ?? managedOffline.last
    }

    /// Whether a dark screen is a display mid-wake rather than a display that left.
    ///
    /// Two tells, either one enough. A REAL display macOS still enumerates while nothing is lit is a
    /// panel finishing its link negotiation, not one that was unplugged. The ledger's own displays
    /// are excluded from that test deliberately: the public lifecycle provider implements "off" by
    /// MIRRORING, which leaves the display enumerated and dark indefinitely, so counting it as
    /// "coming back" would stall the net every single time it is needed.
    ///
    /// And a machine that just woke gets the benefit of the doubt whatever the list says, because an
    /// external can vanish from it entirely for a second or two while the link comes back — which is
    /// precisely the window in which the net used to panic and light the built-in.
    private static func isDisplayOnItsWayBack(_ context: Context) -> Bool {
        let owned = Set(context.managedOffline.map(\.recordID))
        let realDisplayStillEnumerated = context.observations.contains {
            $0.displayClass != .virtual && !owned.contains($0.recordID)
        }
        return realDisplayStillEnumerated || isWakingUp(context)
    }

    // MARK: - Rule 2: the managed-offline ledger across a wake

    /// Whether we are still inside the window where a display's return is macOS's doing.
    ///
    /// Open for the whole sleep/wake transition and for `wakeWindow` seconds after the machine says
    /// it woke — the first half catches the events that beat the notification, the second bounds how
    /// long the benefit of the doubt lasts.
    public static func isWakingUp(_ context: Context) -> Bool {
        if context.isBetweenSleepAndWake { return true }
        guard let lastWakeAt = context.lastWakeAt else { return false }
        return context.now.timeIntervalSince(lastWakeAt) < context.wakeWindow
    }

    /// Ledger entries whose display is lit again and whose "off" is no longer owed.
    ///
    /// Outside a wake, a turned-off display that comes back did so because someone re-enabled it —
    /// in System Settings, from another app — and the app should stop offering to bring it back.
    /// Inside the wake window the same observation means the opposite: macOS relit it on its own,
    /// and this entry is the ONLY record that an "off" is still owed. Forgetting it there is what
    /// made the built-in light up on every wake and stay lit, with nothing left that remembered why
    /// it shouldn't be.
    public static func entriesToForget(_ context: Context) -> Set<DisplayRecordID> {
        guard !isWakingUp(context) else { return [] }
        let visible = Set(visibleSurfaces(in: context.observations).map(\.recordID))
        return Set(context.managedOffline.map(\.recordID).filter(visible.contains))
    }

    /// The "off"s that are owed right now and whether they can be paid yet.
    public struct OfflineIntent: Hashable, Sendable {
        /// Ledger displays that are lit right now and can be put back off safely.
        public var reassert: [ManagedOfflineDisplay]
        /// An "off" is owed but nothing else is lit to take over — ask again after this long.
        public var recheckAfter: TimeInterval?

        public init(reassert: [ManagedOfflineDisplay], recheckAfter: TimeInterval? = nil) {
            self.reassert = reassert
            self.recheckAfter = recheckAfter
        }
    }

    /// Which turned-off displays macOS brought back with the machine, and whether putting them away
    /// again is safe yet.
    ///
    /// The covering-surface test is what makes this obey rule 1 rather than argue with it: an "off"
    /// is only applied once a display the ledger does NOT own is lit, so the last thing standing can
    /// never be the thing we turn off. Until then the answer is "ask again" — which is exactly the
    /// wake case the user sees, where the built-in comes back first and the externals follow.
    public static func offlineIntent(_ context: Context) -> OfflineIntent {
        guard isWakingUp(context) else { return OfflineIntent(reassert: []) }
        let visible = Set(visibleSurfaces(in: context.observations).map(\.recordID))
        let owed = context.managedOffline.filter { offline in
            visible.contains(offline.recordID)
                && context.reassertAttempts[offline.recordID, default: 0]
                    < context.maximumReassertAttempts
        }
        guard !owed.isEmpty else { return OfflineIntent(reassert: []) }
        guard hasCoveringSurface(context) else {
            return OfflineIntent(reassert: [], recheckAfter: context.reassertRecheckStep)
        }
        return OfflineIntent(reassert: owed)
    }

    /// Whether a lit display the ledger doesn't own is present — the screen that stays on once every
    /// owed "off" has been applied.
    private static func hasCoveringSurface(_ context: Context) -> Bool {
        let owned = Set(context.managedOffline.map(\.recordID))
        return visibleSurfaces(in: context.observations).contains { !owned.contains($0.recordID) }
    }
}
