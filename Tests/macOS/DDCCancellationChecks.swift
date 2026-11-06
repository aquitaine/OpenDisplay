import Foundation

@main struct DDCCancellationChecks {
    actor Probe {
        var acquired = false
        func markAcquired() { acquired = true }
    }

    actor ReplyTrace {
        var events: [(name: String, uptime: UInt64)] = []
        @discardableResult func record(_ name: String) -> UInt64 {
            let uptime = DispatchTime.now().uptimeNanoseconds
            events.append((name, uptime))
            return uptime
        }
    }

    static func checkOutstandingReply(minimumNanos: UInt64) async {
        let gate = DDCTransactionGate()
        let trace = ReplyTrace()
        let request = Task {
            guard await gate.acquire() else { preconditionFailure("Request was not cancelled yet") }
            defer { gate.release() }
            let sent = await trace.record("request")
            await DDCTransactionGate.waitForReply(since: sent, minimumNanos: minimumNanos)
            // Models the one permitted post-cancellation I/O: consume the already-requested reply.
            await trace.record(Task.isCancelled ? "discard" : "reply")
        }
        while await trace.events.isEmpty { await Task.yield() }
        request.cancel()
        let next = Task {
            guard await gate.acquire() else { preconditionFailure("Successor was not cancelled") }
            defer { gate.release() }
            await trace.record("next request")
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let pendingEvents = await trace.events
        precondition(pendingEvents.map(\.name) == ["request"],
                     "Cancellation must retain the bus and wait for the outstanding reply deadline")
        await request.value
        await next.value
        let events = await trace.events
        precondition(events.map(\.name) == ["request", "discard", "next request"],
                     "The outstanding reply must be discarded before another request can start")
        precondition(events[1].uptime - events[0].uptime >= minimumNanos,
                     "A cancelled transaction must still honor its reply preparation delay")
        precondition(events[2].uptime >= events[1].uptime)
    }

    static func main() async {
        let start = DispatchTime.now().uptimeNanoseconds
        let pacing = Task {
            await DDCTransactionGate.waitForQuietGap(since: start, minimumNanos: 1_000_000_000)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        pacing.cancel()
        let paced = await pacing.value
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        precondition(!paced, "Cancelled pacing must stop the transaction")
        precondition(elapsed < 500_000_000, "Cancelled pacing must exit promptly")

        let gate = DDCTransactionGate()
        let alreadyCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let acquired = await gate.acquire()
            let paced = await DDCTransactionGate.waitForQuietGap(since: 0, minimumNanos: 50_000_000)
            return (acquired, paced)
        }
        let cancelledAtEntry = await alreadyCancelled.value
        precondition(!cancelledAtEntry.0 && !cancelledAtEntry.1,
                     "Already-cancelled operations must not acquire the bus or proceed without a gap")
        let acquired = await gate.acquire()
        precondition(acquired)
        let cancelledWaiter = Task { await gate.acquire() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        cancelledWaiter.cancel()
        let acquiredAfterCancellation = await cancelledWaiter.value
        precondition(!acquiredAfterCancellation, "A cancelled waiter must finish while the owner holds the bus")

        let probe = Probe()
        let successor = Task {
            guard await gate.acquire() else { preconditionFailure("Successor was not cancelled") }
            defer { gate.release() }
            await probe.markAcquired()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let acquiredBeforeRelease = await probe.acquired
        precondition(!acquiredBeforeRelease, "Cancelling a waiter must not unlock the current owner's bus")
        gate.release()
        await successor.value
        let successorAcquired = await probe.acquired
        precondition(successorAcquired, "The cancelled waiter must not block its successor")

        // Exercise cancellation racing with ownership handoff. Each iteration must leave the
        // gate available, whether cancellation removes the waiter or it receives ownership first.
        for _ in 0..<500 {
            let acquired = await gate.acquire()
            precondition(acquired)
            let waiter = Task {
                if await gate.acquire() { gate.release() }
            }
            await Task.yield()
            waiter.cancel()
            gate.release()
            await waiter.value
        }
        let finalAcquired = await gate.acquire()
        precondition(finalAcquired)
        gate.release()

        let normalStart = DispatchTime.now().uptimeNanoseconds
        let normal = await DDCTransactionGate.waitForQuietGap(since: normalStart, minimumNanos: 50_000_000)
        precondition(normal)
        precondition(DispatchTime.now().uptimeNanoseconds - normalStart >= 50_000_000,
                     "Normal transactions must preserve the quiet gap")
        for delay: UInt64 in [50_000_000, 60_000_000, 100_000_000] {
            await checkOutstandingReply(minimumNanos: delay)
        }
        print("PASS: outstanding reply cleanup, cancelled reply ownership, cancelled pacing, queued cancellation, exclusive ownership, handoff races, normal pacing")
    }
}
