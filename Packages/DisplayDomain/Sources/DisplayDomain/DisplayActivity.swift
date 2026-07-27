import Foundation

/// Whether a display counts as an *active surface* — one the user still has, and can still see
/// something on once they touch the keyboard.
///
/// This exists because `CGDisplayIsActive` answers a narrower question than it appears to: it
/// reports false for a display that is merely ASLEEP. Reading it directly makes an idle Mac look
/// identical to a Mac with no displays at all, which is catastrophic for the always-one-active
/// safety net: on every sleep it would conclude the user is stranded, "recover" a display the user
/// deliberately turned off, and clear the ledger that remembered it — so the *next* real
/// disconnect has nothing left to restore. A sleeping display is a present, usable surface.
public enum DisplayActivity {
    /// `isActive` for an ONLINE display. Asleep counts as active: sleep is a power state, not a
    /// topology change, and the panel lights up again on the next keypress. A display that is
    /// genuinely gone (unplugged, or logically disabled) is absent from the online list entirely,
    /// so it never reaches this function.
    public static func isActiveSurface(cgIsActive: Bool, cgIsAsleep: Bool) -> Bool {
        cgIsActive || cgIsAsleep
    }
}
