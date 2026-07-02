import Foundation

/// Edge-triggered policy for "auto-disconnect the built-in panel when an external connects" (Issue 5)
/// — the project's original use case, made automatic.
///
/// It fires only on the **rising edge** of external presence (none → some): the moment the first
/// external arrives is when the built-in should turn off. Plugging in a *second* external (some →
/// more) leaves presence "some", so no new edge fires and the built-in isn't disturbed again. Pure
/// decision logic — actually turning the built-in off (through the gated coordinator) and bringing it
/// back when the last external leaves (the existing always-one-active safety net) are the host's job.
public struct AutoDisconnectBuiltInPolicy {
    private var externalPresent: Bool

    public init(externalPresent: Bool = false) {
        self.externalPresent = externalPresent
    }

    /// Re-seed the tracked presence *without* firing — e.g. to the launch topology — so the next
    /// change is compared against the true prior state and an already-connected external isn't
    /// mistaken for a fresh arrival.
    public mutating func seed(externalPresent: Bool) {
        self.externalPresent = externalPresent
    }

    /// Feed the latest `(enabled, externalPresent)` on every topology change. Returns true exactly when
    /// an external just arrived (none → some) while the policy is enabled — the moment to turn the
    /// built-in off. Always updates the tracked presence (even when disabled) so edges stay accurate.
    public mutating func onTopologyChange(enabled: Bool, externalPresent: Bool) -> Bool {
        let arrived = !self.externalPresent && externalPresent
        self.externalPresent = externalPresent
        return enabled && arrived
    }
}
