import Foundation

/// Pure decision core for `opendisplay lid` (Issue #34). Reuses the exact two signals Adaptive
/// Display already senses for its schedule fallback (`AdaptiveDisplayPolicy.Input.builtInPresent` /
/// `.ambientLux`, see `AdaptiveDisplay.swift`) rather than introducing a new lid sensor: a built-in
/// panel that's actively displaying settles the question outright (lid must be open), and a readable
/// ambient-light sensor means the lid is open even with the panel off (the "internal display off,
/// Mac keyboard" setup) — the sensor keeps reporting only while the lid is open.
public enum LidStatePolicy {
    public enum State: String, Hashable, Sendable, Codable {
        case open
        case closed
    }

    /// Decides the lid state from the two signals above, or nil when neither settles it — this Mac
    /// has no built-in panel to reason about at all (a desktop Mac), so there is nothing to call
    /// "open" or "closed". `hasBuiltInPanel` is best-effort: `closed` is inferred (not directly
    /// sensed) whenever a built-in panel exists but neither signal reads as open.
    public static func evaluate(
        builtInIsActive: Bool, hasBuiltInPanel: Bool, ambientLux: Double?
    ) -> State? {
        if builtInIsActive { return .open }
        if ambientLux != nil { return .open }
        return hasBuiltInPanel ? .closed : nil
    }
}
