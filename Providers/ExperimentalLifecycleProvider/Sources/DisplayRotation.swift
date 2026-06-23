#if os(macOS)
import CoreGraphics
import Foundation

/// EXPERIMENTAL, opt-in only. Rotates a display via the private SkyLight `SLSSetDisplayRotation`,
/// using ONLY the two-argument ABI corroborated by the MIT-licensed `knoll` project (recovered by
/// SkyLight disassembly): `CGError SLSSetDisplayRotation(CGDirectDisplayID, int32_t)`. No other
/// signature is attempted, and there is no IOKit fallback. The symbol is resolved at runtime, so an
/// absent symbol degrades to "unavailable" rather than crashing.
///
/// This lives in the experimental module and is therefore excluded from the public-API-only / App
/// Store build (App Store guideline 2.5.1). It must never run unless explicitly enabled, and callers
/// should invoke it from a short-lived helper process after their own safety validation — a crash in
/// the WindowServer client path then kills only the helper.
public struct SkyLightDisplayRotator {
    /// `CGError SLSSetDisplayRotation(CGDirectDisplayID, int32_t)`.
    private typealias SetRotationFn = @convention(c) (CGDirectDisplayID, Int32) -> Int32
    private let setRotationFn: SetRotationFn?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        setRotationFn = handle
            .flatMap { dlsym($0, "SLSSetDisplayRotation") }
            .map { unsafeBitCast($0, to: SetRotationFn.self) }
    }

    /// True if the rotation symbol resolved on this OS build.
    public var isAvailable: Bool { setRotationFn != nil }

    /// Performs the rotation inside a normal Core Graphics configuration transaction (knoll's usage),
    /// returning the raw CGError-style result, or a negative sentinel if the symbol is absent or the
    /// transaction couldn't open. Performs NO safety validation — the helper/caller must validate the
    /// angle (0/90/180/270) and display safety first, and verify the result afterwards.
    @discardableResult
    public func rotate(_ degrees: Int32, displayID: CGDirectDisplayID) -> Int32 {
        guard let setRotationFn else { return -1 }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return -2 }
        let result = setRotationFn(displayID, degrees)
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else { return -3 }
        return result
    }
}
#endif
