import Foundation

/// Pure decision core for FaceLight — the "turn this monitor into a video-call fill light" hotkey
/// (DDC brightness/contrast to max, plus a translucent warm click-through overlay — see
/// `overlayAlpha` for why it stops short of opaque). One press activates it and remembers the
/// display's prior brightness/contrast; the next press restores exactly that state.
///
/// The restore ledger this policy produces (`ToggleResult.priorStateToPersist`) belongs in
/// `OpenDisplaySettings.faceLightPriorStateByDisplay`, written BEFORE the max-out hardware writes
/// land and cleared only after a confirmed restore — the same persist-before-write,
/// clear-after-restore invariant `AdaptiveDisplayPolicy` uses for its evening-warmth day-preset
/// ledger, so a crash or relaunch mid-FaceLight still recovers the display's real prior state
/// instead of stranding it at max brightness. ::
///
///     toggle(owedPriorState: nil, liveBrightness: 0.4, liveContrast: 0.5)
///     ok: isNowActive: true,  brightnessWrite: 1.0, contrastWrite: 1.0, priorStateToPersist: (0.4, 0.5)
///
///     toggle(owedPriorState: PriorState(brightness: 0.4, contrast: 0.5), liveBrightness: 1.0, liveContrast: 1.0)
///     ok: isNowActive: false, brightnessWrite: 0.4, contrastWrite: 0.5, priorStateToPersist: nil
///
/// All hardware writes, overlay presentation, and persistence are the caller's job (`AppModel`) —
/// this type only decides what those writes and ledger updates should be.
public enum FaceLightPolicy {
    /// A display's brightness/contrast at the moment FaceLight turned it on, owed back on the next
    /// press. `contrast` is nil when the display has no DDC contrast channel to remember — those
    /// displays get the overlay-only version of FaceLight (no contrast write to undo).
    public struct PriorState: Hashable, Sendable, Codable {
        public var brightness: Float
        public var contrast: Float?

        public init(brightness: Float, contrast: Float? = nil) {
            self.brightness = brightness
            self.contrast = contrast
        }
    }

    /// What one hotkey/menu press should do: the writes to issue, and how the restore ledger entry
    /// for this display should change. `priorStateToPersist` replaces the ledger entry outright — a
    /// non-nil value stores it (activating), nil clears it (restoring); there is no third case.
    public struct ToggleResult: Hashable, Sendable {
        public var isNowActive: Bool
        public var brightnessWrite: Float?
        public var contrastWrite: Float?
        public var priorStateToPersist: PriorState?

        public init(isNowActive: Bool, brightnessWrite: Float?, contrastWrite: Float?,
                    priorStateToPersist: PriorState?) {
            self.isNowActive = isNowActive
            self.brightnessWrite = brightnessWrite
            self.contrastWrite = contrastWrite
            self.priorStateToPersist = priorStateToPersist
        }
    }

    /// Kelvin used for the fill light's warm-white tint — the colour-temperature curve's warmest
    /// stop (candle-light), the look a video-call fill light needs.
    public static let overlayKelvin: Float = ColorTemperatureCurve.minKelvin

    /// Opacity for the fill-light overlay. A video-call fill light has two competing jobs: throw as
    /// much warm light off the panel as possible, and leave on-screen content (the call window
    /// itself, on a single-monitor setup) legible underneath. Full opacity (1.0) wins the first job
    /// and completely fails the second — the screen becomes a blind warm-white slab. 0.5 is the
    /// midpoint of that trade-off: an even wash where the overlay dominates the panel's visual
    /// output (the light-source job), while content underneath stays readable through it — and
    /// brightness/contrast are simultaneously maxed by `toggle`, which raises the panel's own output
    /// enough to carry legibility even under a 50% warm wash on top of it. ::
    ///
    ///     ok:   0.5 — strong warm wash, call window still visible through it
    ///     flag: 1.0 — opaque; screen goes blind, feature unusable on one monitor
    ///     flag: 0.2 — barely tinted; too little extra light for a fill light
    public static let overlayAlpha: Float = 0.5

    /// One hotkey/menu press: toggle FaceLight for a display. `owedPriorState` is that display's
    /// current ledger entry (nil means FaceLight is off for it); `liveBrightness`/`liveContrast` are
    /// its CURRENT values, read fresh so an off-to-on press remembers what's really on screen right
    /// now rather than a stale cache.
    public static func toggle(owedPriorState: PriorState?, liveBrightness: Float,
                              liveContrast: Float?) -> ToggleResult {
        if let owedPriorState {
            return ToggleResult(isNowActive: false, brightnessWrite: owedPriorState.brightness,
                                contrastWrite: owedPriorState.contrast, priorStateToPersist: nil)
        }
        let priorState = PriorState(brightness: liveBrightness, contrast: liveContrast)
        return ToggleResult(isNowActive: true, brightnessWrite: 1.0,
                            contrastWrite: liveContrast != nil ? 1.0 : nil,
                            priorStateToPersist: priorState)
    }
}
