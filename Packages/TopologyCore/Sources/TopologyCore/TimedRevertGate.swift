import Foundation

/// A macOS-style "Keep these settings?" timed auto-revert gate for an arrangement-altering change
/// (resolution / mirror / set-main). The change is applied immediately; a captured "before" state and
/// a deadline are held, and unless the user confirms within the window the prior state is restored.
///
/// This is pure decision logic — capturing the before-state, applying the change, and restoring it are
/// the host's side effects. The gate's job is to make the keep-vs-revert decision resolve **exactly
/// once**: a confirm after the timeout can't un-revert, a timeout after a confirm can't double-restore.
/// That single guarantee is what stops a bad resolution from stranding a display while still never
/// reverting a change the user explicitly accepted. Mirrors the rotation marker/rollback pattern.
public struct TimedRevertGate<State: Equatable>: Equatable {
    public enum Resolution: String, Equatable, Sendable { case pending, kept, reverted }

    /// The arrangement to restore if the change isn't confirmed in time.
    public let before: State
    /// When the window expires (auto-revert fires at or after this instant).
    public let deadline: Date
    public private(set) var resolution: Resolution = .pending

    public init(before: State, deadline: Date) {
        self.before = before
        self.deadline = deadline
    }

    public var isPending: Bool { resolution == .pending }

    /// User accepted the change. Returns true iff this call resolved a pending gate to `.kept`.
    @discardableResult
    public mutating func confirm() -> Bool {
        guard resolution == .pending else { return false }
        resolution = .kept
        return true
    }

    /// Explicit "revert now". Returns the `before` state to restore, or nil if already resolved — so
    /// the host restores at most once regardless of how confirm/revert/tick interleave.
    @discardableResult
    public mutating func revert() -> State? {
        guard resolution == .pending else { return nil }
        resolution = .reverted
        return before
    }

    /// Drives the countdown. If `now` has reached the deadline while still pending, resolves to
    /// `.reverted` and returns the `before` state to restore; otherwise nil (still waiting, or already
    /// resolved). Idempotent past resolution.
    @discardableResult
    public mutating func tick(now: Date) -> State? {
        guard resolution == .pending, now >= deadline else { return nil }
        resolution = .reverted
        return before
    }

    /// Whole seconds remaining until the deadline (never negative), for the countdown label.
    public func secondsRemaining(now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }
}
