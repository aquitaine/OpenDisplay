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

    /// `CGDisplayVendorNumber` for macOS's synthetic placeholder: the four bytes spell "unkn".
    public static let placeholderVendor: UInt32 = 0x756E_6B6E
    /// `CGDisplayModelNumber` for the same: the four bytes spell "virt".
    public static let placeholderModel: UInt32 = 0x7669_7274

    /// Whether a display is the **phantom** macOS synthesizes to keep the window server alive when
    /// every real display has gone — e.g. the last external is unplugged while the built-in is
    /// logically disabled.
    ///
    /// This is why the always-one-active safety net could never fire: it waited for the online
    /// display count to reach zero, and macOS never lets it. It substitutes this placeholder
    /// instead — active, main, and showing the user absolutely nothing. Captured live: vendor
    /// "unkn", model "virt", serial 0, and exactly ONE display mode where real panels report
    /// dozens. The vendor/model tags are macOS's own marker; the single-mode check corroborates.
    public static func isVirtualPlaceholder(vendorNumber: UInt32, modelNumber: UInt32,
                                            modeCount: Int) -> Bool {
        (vendorNumber == placeholderVendor && modelNumber == placeholderModel) || modeCount == 1
    }
}
