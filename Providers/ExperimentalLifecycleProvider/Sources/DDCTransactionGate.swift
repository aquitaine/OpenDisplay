import Foundation

/// FIFO ownership for a DDC request/reply transaction. The lock only protects the queue; it is
/// never held across a suspension or an I2C call. Cancellation removes a queued waiter, while an
/// owner (including one cancelled during handoff) is solely responsible for releasing its turn.
final class DDCTransactionGate: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private let mutex = NSLock()
    private var owned = false
    private var waiters: [Waiter] = []

    func acquire() async -> Bool {
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate: Bool? = mutex.withLock {
                    guard !Task.isCancelled else { return false }
                    if !owned {
                        owned = true
                        return true
                    }
                    waiters.append(Waiter(id: id, continuation: continuation))
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            self.cancelWaiter(id)
        }
        guard acquired else { return false }
        // Cancellation may race with release handing ownership to this continuation. Only after
        // a successful acquire may this task release; removing a queued waiter must never do so.
        guard !Task.isCancelled else { release(); return false }
        return true
    }

    func release() {
        let next: Waiter? = mutex.withLock {
            precondition(owned, "Releasing an unowned DDC bus")
            if waiters.isEmpty { owned = false; return nil }
            return waiters.removeFirst()
        }
        next?.continuation.resume(returning: true)
    }

    private func cancelWaiter(_ id: UUID) {
        let waiter: Waiter? = mutex.withLock {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return waiters.remove(at: index)
        }
        waiter?.continuation.resume(returning: false)
    }

    /// Once a Get request is sent, its reply must be consumed before ownership can change.
    /// This deadline deliberately ignores task cancellation; a cancelled owner waits once, then
    /// reads/discards the outstanding reply without issuing another command or counting failures.
    static func waitForReply(since uptime: UInt64, minimumNanos: UInt64) async {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- uptime
        guard elapsed < minimumNanos else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: DispatchTime(uptimeNanoseconds: uptime &+ minimumNanos)
            ) {
                continuation.resume()
            }
        }
    }

    /// Called only by the bus owner, so the previous transaction's timestamp cannot move while
    /// waiting. A cancelled sleep exits immediately instead of spinning until the deadline.
    static func waitForQuietGap(since uptime: UInt64, minimumNanos: UInt64) async -> Bool {
        guard !Task.isCancelled else { return false }
        if uptime != 0 {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- uptime
            if elapsed < minimumNanos {
                do {
                    try await Task.sleep(nanoseconds: minimumNanos - elapsed)
                } catch {
                    return false
                }
            }
        }
        return !Task.isCancelled
    }
}
