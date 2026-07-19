import Foundation

/// How the software dimming slider darkens a display beyond (or instead of) its backlight.
public enum DimmingMethod: String, Codable, Sendable, CaseIterable {
    /// Scale the gamma table (the original behavior). Dims everything including the menu bar, but
    /// bottoms out at the provider's 0.15 floor.
    case gamma
    /// A black, click-through overlay window at adjustable opacity. Independent of the gamma table
    /// (so it composes with software brightness), capped below full black.
    case overlay
    /// Gamma first, then overlay on top — darker than either alone.
    case combined
}

/// Splits one dim level into its gamma and overlay components. Pure so the darkness curve — floors,
/// caps, and the combined handoff point — is unit-tested; the app just applies the two outputs.
public enum DimmingComposer {
    /// Gamma scale never goes below this (matches the provider's floor) so a gamma-only dim can't
    /// black out a display.
    public static let gammaFloor: Float = 0.15
    /// The overlay never becomes fully opaque, so even maximum combined dimming leaves the screen
    /// faintly visible and the user can always find their way back.
    public static let overlayAlphaCap: Float = 0.9
    /// In `.combined`, the fraction of the strength range the gamma channel absorbs before the
    /// overlay starts stacking on top.
    public static let combinedGammaShare: Float = 0.55

    public struct Split: Equatable, Sendable {
        /// Gamma scale to apply, `gammaFloor`...1 (1 = untouched).
        public let gammaLevel: Float
        /// Overlay opacity to apply, 0...`overlayAlphaCap` (0 = no overlay window).
        public let overlayAlpha: Float

        public init(gammaLevel: Float, overlayAlpha: Float) {
            self.gammaLevel = gammaLevel
            self.overlayAlpha = overlayAlpha
        }
    }

    /// `level` is the dim slider's value, 1 (no dimming) down to 0 (maximum), clamped.
    public static func split(method: DimmingMethod, level: Float) -> Split {
        let level = min(max(level, 0), 1)
        let strength = 1 - level
        switch method {
        case .gamma:
            return Split(gammaLevel: max(level, gammaFloor), overlayAlpha: 0)
        case .overlay:
            return Split(gammaLevel: 1, overlayAlpha: strength * overlayAlphaCap)
        case .combined:
            let gammaPortion = min(strength / combinedGammaShare, 1)
            let overlayPortion = max(0, (strength - combinedGammaShare) / (1 - combinedGammaShare))
            return Split(
                gammaLevel: max(1 - gammaPortion * (1 - gammaFloor), gammaFloor),
                overlayAlpha: overlayPortion * overlayAlphaCap)
        }
    }
}
