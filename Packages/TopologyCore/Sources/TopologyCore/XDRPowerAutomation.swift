import Foundation

/// Power-aware automations for XDR Brightness (Labs, Issue #35): the rules that turn a boost back
/// off on their own, and the memory that can put it back.
///
/// The boost is expensive in a way the slider doesn't show — it drives the backlight to its HDR
/// maximum, which is the single largest power draw a laptop panel has, and it warms the panel. Left
/// on, it quietly eats a battery. So the feature grows the same power gating every comparable
/// unlocker ships: drop the boost on battery, below a charge cutoff, in Low Power Mode, or after a
/// time limit — each opt-in, each independent.
///
/// The whole decision is pure and lives here so it can be exercised off-device: the host feeds a
/// `PowerSnapshot` (IOKit power sources + `ProcessInfo`'s Low Power Mode flag), the current boost
/// fraction, and whether the built-in panel is still an active surface; it gets back one `Decision`
/// and performs it through the app's single boost funnel.
///
/// Two families of rule, and the difference between them is the whole design:
///
/// * **Battery family** (on battery / below cutoff / Low Power Mode) — conditions that are *true
///   for a while and then stop being true*. Suspending remembers the fraction, so plugging back in
///   can restore exactly the brightness the user had. This is what `restoreOnPower` governs.
/// * **Auto-off timer, and the built-in going away** — events, not conditions. There is nothing to
///   wait for and nothing to come back from, so they clear the boost without remembering it. The
///   timer expiring means "you've had this long enough"; restoring it a moment later would defeat
///   the rule entirely.
///
/// Any manual change to the boost (`noteUserSet`) wins over everything remembered: it restarts the
/// auto-off clock and drops any pending restore, because a fraction the user just chose is the
/// fraction they want — the app must never overwrite it later with a stale one.
public struct XDRPowerAutomation {
    /// The user's automation settings, mirroring the persisted `OpenDisplaySettings` fields. A value
    /// rather than a stored dependency so `evaluate` always reads the live settings and a toggle
    /// flipped mid-suspension takes effect on the very next pass.
    public struct Rules: Hashable, Sendable {
        /// Zero the boost whenever the Mac is running on battery.
        public var disableOnBattery: Bool
        /// Zero the boost when, on battery, the charge is at or below this percentage. Nil = never.
        /// Independent of `disableOnBattery` — a user can allow the boost on battery right up until
        /// the charge gets low.
        public var lowBatteryCutoffPercent: Int?
        /// Zero the boost while macOS Low Power Mode is on. The user has asked the whole system to
        /// spend less energy; a 2× backlight is the loudest way to ignore that.
        public var disableInLowPowerMode: Bool
        /// Zero the boost this many minutes after it was engaged. Nil = never.
        public var autoOffMinutes: Int?
        /// Put a battery-family-suspended boost back when every battery-family condition clears.
        /// On by default: without it the rules above are a one-way trip that silently re-dims the
        /// screen for the rest of the session.
        public var restoreOnPower: Bool

        public init(
            disableOnBattery: Bool = false,
            lowBatteryCutoffPercent: Int? = nil,
            disableInLowPowerMode: Bool = false,
            autoOffMinutes: Int? = nil,
            restoreOnPower: Bool = true
        ) {
            self.disableOnBattery = disableOnBattery
            self.lowBatteryCutoffPercent = lowBatteryCutoffPercent
            self.disableInLowPowerMode = disableInLowPowerMode
            self.autoOffMinutes = autoOffMinutes
            self.restoreOnPower = restoreOnPower
        }

        /// True when at least one battery-family rule is armed — the host uses this to decide
        /// whether to hold IOKit power-source listeners at all. The auto-off timer needs no power
        /// monitoring, so it deliberately doesn't count.
        public var needsPowerMonitoring: Bool {
            disableOnBattery || lowBatteryCutoffPercent != nil || disableInLowPowerMode
        }
    }

    /// What the machine's power state looks like right now. A desktop Mac has no battery source, so
    /// it reports `onBattery: false, batteryPercent: nil` and every battery-family rule degrades to
    /// a no-op without any host-side special-casing.
    public struct PowerSnapshot: Hashable, Sendable {
        public var onBattery: Bool
        /// Charge 0...100, or nil when no battery source is readable. Nil NEVER triggers the cutoff:
        /// an unreadable charge is not a low charge, and guessing would turn the boost off on
        /// desktops and during the first moments after a power-source change.
        public var batteryPercent: Int?
        public var lowPowerMode: Bool

        public init(onBattery: Bool = false, batteryPercent: Int? = nil, lowPowerMode: Bool = false) {
            self.onBattery = onBattery
            self.batteryPercent = batteryPercent
            self.lowPowerMode = lowPowerMode
        }

        /// A machine on wall power with Low Power Mode off — the state a desktop reports, and the
        /// one a laptop returns to when it's plugged back in.
        public static let onWallPower = PowerSnapshot()
    }

    /// Why an automation zeroed the boost. Carries the numbers the user needs to recognise the
    /// event ("battery at 18%"), so the host never has to reconstruct them after the fact.
    public enum SuspensionReason: Hashable, Sendable {
        case onBattery
        case lowBattery(percent: Int)
        case lowPowerMode
        case autoOffTimer
        /// The built-in panel stopped being an active surface (lid closed, clamshell, display
        /// turned off) while a fraction was still set. Cleanup, not a power rule.
        case builtInInactive

        /// True for the reasons a `restore` can undo: conditions that end, rather than events.
        public var isBatteryFamily: Bool {
            switch self {
            case .onBattery, .lowBattery, .lowPowerMode: return true
            case .autoOffTimer, .builtInInactive: return false
            }
        }

        /// The notification body for this reason, or nil when the event isn't worth telling the user
        /// about. `builtInInactive` is the nil case on purpose: the user just closed the lid or
        /// unplugged a screen, so a "we turned the boost off" alert is noise — and it would be
        /// waiting for them on the next wake, about a display they can no longer see.
        public var notificationBody: String? {
            switch self {
            case .onBattery:
                return "Now running on battery power."
            case .lowBattery(let percent):
                return "Battery at \(percent)%."
            case .lowPowerMode:
                return "Low Power Mode is on."
            case .autoOffTimer:
                return "The auto-off timer elapsed."
            case .builtInInactive:
                return nil
            }
        }
    }

    /// What the host should do about the boost this pass.
    public enum Decision: Hashable, Sendable {
        /// Nothing to do — including every repeat evaluation in unchanged conditions.
        case none
        /// Zero the boost through the normal funnel. The reason is already recorded in the state.
        case suspend(reason: SuspensionReason)
        /// Put this exact fraction back, through the same funnel a user's slider uses.
        case restore(fraction: Float)
    }

    /// The battery cutoffs the settings UI offers, in "Never, then…" order. Kept here so the UI and
    /// the policy can never drift apart on what a valid cutoff is.
    public static let lowBatteryCutoffOptions = [10, 20, 30, 50]
    /// The auto-off durations the settings UI offers (minutes).
    public static let autoOffMinuteOptions = [15, 30, 60, 120]
    /// Title shared by every automation notification; the reason supplies the body.
    public static let notificationTitle = "XDR Brightness turned off"

    /// A boost the battery family took away and owes back: the exact fraction, and which condition
    /// took it. Only battery-family reasons are ever stored — the timer and the built-in leaving
    /// clear the boost outright.
    private struct Suspension {
        var fraction: Float
        var reason: SuspensionReason
    }

    private var suspension: Suspension?
    /// When the live boost was engaged — the auto-off clock's zero. Set by a user's own set and by
    /// a restore (a restored boost starts its full allowance again; it is, from the panel's point of
    /// view, a fresh engagement), cleared whenever the boost goes to zero by any route.
    private var engagedAt: Date?

    public init() {}

    /// The fraction currently owed back by a battery-family suspension, if any. Exposed for the
    /// host's UI/diagnostics and for tests; a nil here means nothing is pending.
    public var suspendedFraction: Float? { suspension?.fraction }

    /// Why the boost is currently suspended, if it is.
    public var suspensionReason: SuspensionReason? { suspension?.reason }

    /// Records a boost the **user** set (slider, menu toggle, or any other explicit action): the
    /// auto-off clock restarts from `now`, and anything the automations were owing is forgotten.
    /// The host must NOT call this for its own automation writes — a suspend that reported itself as
    /// a user set would erase the very fraction it just saved, and a restore would re-arm nothing.
    public mutating func noteUserSet(fraction: Float, at now: Date) {
        suspension = nil
        engagedAt = fraction > 0 ? now : nil
    }

    /// When the auto-off timer should next fire, so the host can arm a single `RecheckTimer` instead
    /// of polling. Nil when no boost is engaged or the timer rule is off.
    public func autoOffDeadline(rules: Rules) -> Date? {
        guard let engagedAt, let minutes = rules.autoOffMinutes, minutes > 0 else { return nil }
        return engagedAt.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    /// The one decision point. Call it on every power-state change, Low Power Mode change, topology
    /// change, timer fire, and settings change — it is idempotent, so calling it more often than
    /// needed costs nothing and missing an edge is the only real failure mode.
    ///
    /// - Parameters:
    ///   - rules: the user's live automation settings.
    ///   - power: the current power snapshot.
    ///   - boostFraction: the boost in effect now (nil or 0 = off).
    ///   - builtInActive: whether the built-in panel is still an active surface.
    ///   - now: the clock, injected so tests can stand at any point around a deadline.
    public mutating func evaluate(
        rules: Rules,
        power: PowerSnapshot,
        boostFraction: Float?,
        builtInActive: Bool,
        now: Date
    ) -> Decision {
        let fraction = boostFraction ?? 0
        guard fraction > 0 else { return evaluateWhileOff(rules: rules, power: power,
                                                          builtInActive: builtInActive, now: now) }

        // The panel the boost applies to is gone: clear the stale fraction (the UI reads it, and it
        // would show the slider up on a display that isn't there) and remember nothing. A boost is
        // session state that a lid-close ends, exactly like the relaunch that always starts normal.
        guard builtInActive else {
            suspension = nil
            engagedAt = nil
            return .suspend(reason: .builtInInactive)
        }

        // Battery family first: a machine that's on battery AND past its timer should report the
        // condition it can recover from, so plugging in still puts the boost back.
        if let reason = batteryFamilyReason(rules: rules, power: power) {
            suspension = Suspension(fraction: fraction, reason: reason)
            engagedAt = nil
            return .suspend(reason: reason)
        }

        if let deadline = autoOffDeadline(rules: rules), now >= deadline {
            suspension = nil  // an elapsed allowance is not owed back
            engagedAt = nil
            return .suspend(reason: .autoOffTimer)
        }
        return .none
    }

    /// The half of `evaluate` that runs while no boost is set: the only thing that can happen is a
    /// restore, and only for a battery-family suspension whose conditions have all cleared.
    private mutating func evaluateWhileOff(
        rules: Rules, power: PowerSnapshot, builtInActive: Bool, now: Date
    ) -> Decision {
        guard let pending = suspension else { return .none }
        // Nothing to restore onto — and nothing to come back to later either. Drop it, so a boost
        // suspended on battery can't reappear on a panel the user has since closed the lid on.
        guard builtInActive else {
            suspension = nil
            return .none
        }
        guard rules.restoreOnPower, pending.reason.isBatteryFamily,
              batteryFamilyReason(rules: rules, power: power) == nil else { return .none }
        suspension = nil
        // A boost that comes back has, as far as the panel is concerned, just been engaged: give it
        // the full auto-off allowance rather than an expiry inherited from before the suspension.
        engagedAt = now
        return .restore(fraction: pending.fraction)
    }

    /// The battery-family condition currently in force, or nil when all of them are clear — the same
    /// test used both to suspend and to decide a restore is safe, so the two can never disagree
    /// about what "back on power" means. Order is broadest-first: "on battery" describes the state
    /// better than the cutoff that also happens to be met.
    ///
    /// Note that a rule the user has switched off reads as a cleared condition, so turning
    /// "off on battery" off while suspended restores the boost on the next pass — which is what
    /// disabling a rule that is currently holding the screen dim should do.
    private func batteryFamilyReason(rules: Rules, power: PowerSnapshot) -> SuspensionReason? {
        if rules.disableOnBattery, power.onBattery { return .onBattery }
        if let cutoff = rules.lowBatteryCutoffPercent, power.onBattery,
           let percent = power.batteryPercent, percent <= cutoff {
            return .lowBattery(percent: percent)
        }
        if rules.disableInLowPowerMode, power.lowPowerMode { return .lowPowerMode }
        return nil
    }
}
