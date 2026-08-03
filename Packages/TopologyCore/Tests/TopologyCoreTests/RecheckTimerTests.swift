import XCTest
@testable import TopologyCore

@MainActor
final class RecheckTimerTests: XCTestCase {
    /// Mutable scratch state shared with the timer's work closure (all of it MainActor-confined).
    @MainActor private final class Recorder {
        var runs = 0
        var wasCancelledDuringWork: Bool?
        var survivedAnAwait: Bool?
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testArmedWorkRunsAfterTheDelay() async {
        let timer = RecheckTimer()
        let recorder = Recorder()
        XCTAssertFalse(timer.isArmed)
        timer.arm(after: 0.01) { recorder.runs += 1 }
        XCTAssertTrue(timer.isArmed)
        await waitUntil { recorder.runs == 1 }
        XCTAssertEqual(recorder.runs, 1)
        XCTAssertFalse(timer.isArmed, "a fired timer disarms itself")
    }

    /// The regression this type exists for: work that cancels the timer which scheduled it must
    /// keep running in a live context. Cancellation there is silent — `Task.sleep` returns at once
    /// and every settle/retry loop downstream gives up on its first pass — so the assertion is that
    /// the work is NOT cancelled, both immediately and after an await.
    func testWorkCancellingItsOwnTimerStillRunsUncancelled() async {
        let timer = RecheckTimer()
        let recorder = Recorder()
        timer.arm(after: 0.01) {
            timer.cancel()
            recorder.wasCancelledDuringWork = Task.isCancelled
            try? await Task.sleep(nanoseconds: 20_000_000)
            recorder.survivedAnAwait = !Task.isCancelled
            recorder.runs += 1
        }
        await waitUntil { recorder.runs == 1 }
        XCTAssertEqual(recorder.wasCancelledDuringWork, false)
        XCTAssertEqual(recorder.survivedAnAwait, true)
    }

    func testRearmingReplacesThePendingRecheck() async {
        let timer = RecheckTimer()
        let first = Recorder()
        let second = Recorder()
        timer.arm(after: 5) { first.runs += 1 }
        timer.arm(after: 0.01) { second.runs += 1 }
        await waitUntil { second.runs == 1 }
        XCTAssertEqual(second.runs, 1)
        XCTAssertEqual(first.runs, 0, "the replaced re-check must never fire")
    }

    func testCancelStopsWorkThatHasNotStarted() async {
        let timer = RecheckTimer()
        let recorder = Recorder()
        timer.arm(after: 0.05) { recorder.runs += 1 }
        timer.cancel()
        XCTAssertFalse(timer.isArmed)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.runs, 0)
    }
}
