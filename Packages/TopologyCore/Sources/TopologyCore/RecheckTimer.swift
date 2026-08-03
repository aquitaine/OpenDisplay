import Foundation

/// A one-shot, re-armable "ask again in N seconds" timer.
///
/// The whole point of the type is a separation that is easy to get wrong when this is written
/// inline: the task that WAITS and the task that RUNS the work are never the same task.
///
/// Written the obvious way — a timer task that sleeps and then calls the work directly — the work
/// inherits the timer's cancellation. That is fatal when the work's first act is to cancel the
/// pending re-check, because the pending re-check IS the task it is running in: every timer-driven
/// pass then executes in an already-cancelled context, where `Task.sleep` returns instantly,
/// provider settle loops (`awaitStableGeneration`) give up on their first iteration, and re-poll
/// retries collapse to a single attempt. Nothing throws; the work just quietly stops waiting for
/// anything, and slow-but-successful operations get judged as failures.
///
/// Here the waiting task does nothing but wait. When the delay elapses it clears itself and hands
/// the work to a fresh unstructured task, which does not inherit cancellation — so `cancel()` can
/// only ever stop work that has not started, and work can safely cancel the timer that scheduled it.
@MainActor
public final class RecheckTimer {
    private var waiting: Task<Void, Never>?

    public init() {}

    /// True while a re-check is scheduled and has not yet fired.
    public var isArmed: Bool { waiting != nil }

    /// Schedules `work` to run after `delay`, replacing any re-check still pending.
    public func arm(after delay: TimeInterval, run work: @escaping @MainActor () async -> Void) {
        cancel()
        waiting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.waiting = nil
            Task { await work() }
        }
    }

    /// Drops a pending re-check. A no-op once the work has been handed off.
    public func cancel() {
        waiting?.cancel()
        waiting = nil
    }
}
