import Foundation

/// Maps the XDR Brightness slider onto a gamma-table boost factor (Issue #35).
///
/// The unlock has two halves. First the app presents a tiny always-on EDR frame on the built-in
/// XDR panel, which makes WindowServer raise the physical backlight toward its HDR maximum — and,
/// to keep SDR content looking unchanged, digitally attenuate it by the same ratio (visible as
/// `NSScreen.maximumExtendedDynamicRangeColorComponentValue` ramping above 1). Second, the app
/// scales the display's gamma transfer table up by the boost this policy computes, mapping the
/// attenuated SDR white back toward full drive of the raised backlight — the whole desktop gets
/// genuinely brighter. Table entries saturate at 1.0, so anything the boost pushes past the clip
/// point flattens: HDR content looks clipped while a boost is engaged (the same limitation other
/// XDR unlockers document), which is why the boost never exceeds the backlight's real ratio.
public enum XDRBrightnessPolicy {
    /// Hard cap on the boost, the panel's real SDR→XDR backlight ratio (1600 / 500 nits). The OS
    /// may report more digital headroom than this (16× on some panels), but boosting past what the
    /// backlight physically delivers only clips more of the range for zero extra light.
    public static let maxBoost: Float = 3.2

    /// The gamma boost for a slider `fraction` (0 = off … 1 = maximum), given the display's live
    /// EDR `headroom` (`maximumExtendedDynamicRangeColorComponentValue`). Linear from 1 at
    /// fraction 0 up to the usable ceiling — the smaller of the live headroom and `maxBoost` — so
    /// the slider tracks the backlight as it ramps. Never below 1: headroom ≤ 1 means EDR hasn't
    /// engaged (or the panel has none), and there is nothing to map back up.
    public static func boost(forFraction fraction: Float, headroom: Float) -> Float {
        let fraction = min(max(fraction, 0), 1)
        return max(1, 1 + fraction * (min(headroom, maxBoost) - 1))
    }

    /// True when `boost` meaningfully brightens (beyond float noise) — drives "is XDR active" UI
    /// state and lets a boost of exactly 1 take the untouched formula gamma path.
    public static func isEngaged(boost: Float) -> Bool {
        boost > 1.001
    }
}
