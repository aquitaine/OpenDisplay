import Foundation

/// Creates and releases the OS "prevent display idle-sleep" power assertion. The concrete macOS
/// implementation (in the app) wraps `IOPMAssertionCreateWithName` /
/// `kIOPMAssertionTypePreventUserIdleDisplaySleep` / `IOPMAssertionRelease`; tests inject a fake.
///
/// `createPreventDisplaySleepAssertion` returns an opaque handle (the IOKit `IOPMAssertionID`, a
/// `UInt32`) or `nil` if the OS refused — callers must tolerate a `nil` handle and simply not hold an
/// assertion, never crash.
public protocol PowerAssertionControlling: Sendable {
    func createPreventDisplaySleepAssertion(named name: String) -> UInt32?
    func releaseAssertion(_ handle: UInt32)
}

/// Holds **at most one** "prevent display idle-sleep" assertion, derived from two inputs: whether the
/// user enabled the feature and whether any external display is present. The decision is pure
/// (`enabled && externalPresent`); the side effect is delegated to a `PowerAssertionControlling`
/// backend so the lifecycle is unit-testable off-device.
///
/// Reconciliation is idempotent: re-applying the same effective state is a no-op, so the guard never
/// double-creates or leaks an assertion across connect/disconnect cycles. `releaseAll()` (also called
/// from `deinit`) guarantees the assertion never outlives the guard, covering app teardown/relaunch.
///
/// Not `Sendable`: it holds mutable state and is meant to be driven from a single actor (the app's
/// `@MainActor` model). Tests drive it synchronously.
public final class DisplaySleepGuard {
    private let backend: any PowerAssertionControlling
    private let assertionName: String
    private var handle: UInt32?
    private var enabled = false
    private var externalPresent = false

    public init(
        backend: any PowerAssertionControlling,
        assertionName: String = "OpenDisplay: external display connected"
    ) {
        self.backend = backend
        self.assertionName = assertionName
    }

    /// True while an OS assertion is currently held.
    public var isHoldingAssertion: Bool { handle != nil }

    /// The effective decision: hold the assertion only while enabled *and* an external is present.
    public var shouldHold: Bool { enabled && externalPresent }

    /// Re-evaluate against the latest feature toggle and external-presence state, creating or
    /// releasing the single assertion as needed. Safe to call on every topology change and every
    /// settings change — repeated calls with an unchanged effective state do nothing.
    public func update(enabled: Bool, externalPresent: Bool) {
        self.enabled = enabled
        self.externalPresent = externalPresent
        reconcile()
    }

    private func reconcile() {
        if shouldHold {
            guard handle == nil else { return }
            handle = backend.createPreventDisplaySleepAssertion(named: assertionName)
        } else {
            guard let held = handle else { return }
            backend.releaseAssertion(held)
            handle = nil
        }
    }

    /// Release any held assertion and forget it. Idempotent. Call on app teardown so the assertion
    /// can never outlive the process.
    public func releaseAll() {
        guard let held = handle else { return }
        backend.releaseAssertion(held)
        handle = nil
    }

    deinit { releaseAll() }
}
