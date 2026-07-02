import XCTest
@testable import TopologyCore

/// Records every create/release so tests can assert the assertion is held exactly when expected and
/// that nothing leaks. `liveHandles` is the set of handles created but not yet released.
private final class FakePowerAssertions: PowerAssertionControlling, @unchecked Sendable {
    private(set) var createCount = 0
    private(set) var releaseCount = 0
    private(set) var liveHandles: Set<UInt32> = []
    private(set) var lastName: String?
    /// When true, the OS "refuses" and create returns nil (handle isn't tracked as live).
    var refuse = false
    private var nextHandle: UInt32 = 1

    func createPreventDisplaySleepAssertion(named name: String) -> UInt32? {
        lastName = name
        createCount += 1
        if refuse { return nil }
        let handle = nextHandle
        nextHandle += 1
        liveHandles.insert(handle)
        return handle
    }

    func releaseAssertion(_ handle: UInt32) {
        releaseCount += 1
        liveHandles.remove(handle)
    }
}

final class DisplaySleepGuardTests: XCTestCase {
    func testHoldsOnlyWhenEnabledAndExternalPresent() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)

        // Neither condition: no assertion.
        guardian.update(enabled: false, externalPresent: false)
        XCTAssertFalse(guardian.isHoldingAssertion)

        // Only the toggle: still no assertion (no external to keep awake).
        guardian.update(enabled: true, externalPresent: false)
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertEqual(backend.createCount, 0)

        // Only an external, toggle off: no assertion.
        guardian.update(enabled: false, externalPresent: true)
        XCTAssertFalse(guardian.isHoldingAssertion)

        // Both: assertion held.
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertTrue(guardian.isHoldingAssertion)
        XCTAssertEqual(backend.createCount, 1)
        XCTAssertEqual(backend.liveHandles.count, 1)
    }

    func testReleasesWhenLastExternalRemoved() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertTrue(guardian.isHoldingAssertion)

        guardian.update(enabled: true, externalPresent: false)
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertEqual(backend.releaseCount, 1)
        XCTAssertTrue(backend.liveHandles.isEmpty)
    }

    func testReleasesWhenToggledOff() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertTrue(guardian.isHoldingAssertion)

        guardian.update(enabled: false, externalPresent: true)
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertEqual(backend.releaseCount, 1)
        XCTAssertTrue(backend.liveHandles.isEmpty)
    }

    func testReevaluationIsIdempotentNoDoubleCreate() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)
        // A burst of topology/settings re-evaluations with the same effective state.
        for _ in 0..<5 {
            guardian.update(enabled: true, externalPresent: true)
        }
        XCTAssertEqual(backend.createCount, 1, "should create the assertion only once")
        XCTAssertEqual(backend.liveHandles.count, 1)
    }

    func testNoLeaksAcrossConnectDisconnectCycles() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)
        guardian.update(enabled: true, externalPresent: false)
        // Plug/unplug an external repeatedly.
        for _ in 0..<10 {
            guardian.update(enabled: true, externalPresent: true)
            guardian.update(enabled: true, externalPresent: false)
        }
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertTrue(backend.liveHandles.isEmpty, "every assertion created must be released")
        XCTAssertEqual(backend.createCount, backend.releaseCount)
        XCTAssertEqual(backend.createCount, 10)
    }

    func testReleaseAllReleasesHeldAssertion() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend)
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertTrue(guardian.isHoldingAssertion)

        guardian.releaseAll()
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertTrue(backend.liveHandles.isEmpty)
        // Idempotent: a second release-all does nothing.
        guardian.releaseAll()
        XCTAssertEqual(backend.releaseCount, 1)
    }

    func testToleratesOSRefusalWithoutCrashOrLeak() {
        let backend = FakePowerAssertions()
        backend.refuse = true
        let guardian = DisplaySleepGuard(backend: backend)
        guardian.update(enabled: true, externalPresent: true)
        // Create was attempted but the OS refused; no handle held, nothing to leak.
        XCTAssertEqual(backend.createCount, 1)
        XCTAssertFalse(guardian.isHoldingAssertion)
        XCTAssertTrue(backend.liveHandles.isEmpty)

        // Recovering: once the OS cooperates, a later update acquires cleanly.
        backend.refuse = false
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertTrue(guardian.isHoldingAssertion)
        XCTAssertEqual(backend.liveHandles.count, 1)
    }

    func testDeinitReleasesAssertion() {
        let backend = FakePowerAssertions()
        do {
            let guardian = DisplaySleepGuard(backend: backend)
            guardian.update(enabled: true, externalPresent: true)
            XCTAssertEqual(backend.liveHandles.count, 1)
        }
        // Guard deallocated → its assertion must be gone (no leak across "relaunch").
        XCTAssertTrue(backend.liveHandles.isEmpty)
        XCTAssertEqual(backend.releaseCount, 1)
    }

    func testAssertionNameIsDescriptive() {
        let backend = FakePowerAssertions()
        let guardian = DisplaySleepGuard(backend: backend, assertionName: "OpenDisplay test")
        guardian.update(enabled: true, externalPresent: true)
        XCTAssertEqual(backend.lastName, "OpenDisplay test")
    }
}
