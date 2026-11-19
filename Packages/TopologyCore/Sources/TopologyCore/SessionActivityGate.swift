import Foundation

/// Whether this app's login session is the one at the console — and therefore whether it may change
/// anything about the displays on its own (Issue #50, fast user switching).
///
/// With fast user switching every logged-in user keeps their own copy of OpenDisplay running. The
/// displays are not per-user: the panels, the cables and the monitors' DDC registers are shared by
/// every session, and only the console session is looking at them. A background copy that keeps
/// reacting to topology events — lighting a "stranded" fallback, re-asserting its user's "off"s,
/// restoring its Protected Layout, writing adaptive brightness over DDC — is fighting the user who is
/// actually sitting there. That is what makes a display flash, or show up twice in System Settings,
/// right after a switch.
///
/// The rule this encodes is short: **a session that is not on the console makes no automatic display
/// changes.** It keeps observing, so its model is current when its user comes back, and it keeps its
/// user's standing decisions (the managed-offline ledger) rather than reading the other user's
/// arrangement as its own user changing their mind. Coming back is treated like a wake: the display
/// list is re-read, DDC bindings are dropped, and the app converges on its user's arrangement again.
///
/// Pure and clock-free: the host feeds the session notifications in, and gets back the edge.
public struct SessionActivityGate: Hashable, Sendable {
    /// The edge produced by an `update`.
    public enum Transition: Hashable, Sendable {
        /// Nothing changed (a repeated or spurious notification).
        case unchanged
        /// The user switched away: stop every automatic display action now.
        case suspended
        /// The user is back at the console: re-read the world and converge on it.
        case resumed
    }

    /// True while this session owns the console.
    public private(set) var isActive: Bool

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }

    /// Feeds the latest session state in; returns the edge, if any. Idempotent, so it is safe to
    /// feed both the notifications and a fresh console query without double-firing.
    public mutating func update(isActive: Bool) -> Transition {
        guard isActive != self.isActive else { return .unchanged }
        self.isActive = isActive
        return isActive ? .resumed : .suspended
    }

    /// Whether automatic display actions may run: the always-one-active safety net, the ledger
    /// re-assert, Protected Layout, auto-disconnect of the built-in, adaptive / group / app-preset
    /// brightness, and display notifications. Explicit user actions are not gated here — a session
    /// that isn't on the console has no user at the keyboard to take them.
    public var permitsAutomaticDisplayActions: Bool { isActive }

    /// Whether a display change seen right now should be attributed to someone other than this
    /// session's user. While switched away it always is: the other user's session (or macOS setting
    /// it up) relit or rearranged the displays, so the ledger must neither forget an owed "off" nor
    /// treat the change as this user's doing.
    public var attributesDisplayChangesElsewhere: Bool { !isActive }

    /// Reads the console flag from the current session's info (`kCGSessionOnConsoleKey`). An unknown
    /// answer — no window-server session dictionary, or no flag in it — counts as active: the gate
    /// exists to stop a background copy from interfering, and wrongly suspending a foreground copy
    /// would silently switch off every automation for the user who is actually there.
    public static func isActive(onConsole: Bool?) -> Bool {
        onConsole ?? true
    }
}
