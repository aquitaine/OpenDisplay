#if os(macOS)
import CoreGraphics
import Foundation

/// Hardware display brightness via the private `DisplayServices` framework, resolved with `dlsym` at
/// runtime — so it links without a private-framework dependency and degrades to "unavailable" when
/// the symbols are absent. This is the path Apple's own brightness HUD uses: it drives the built-in
/// panel and any external the framework recognizes (many do not — those need DDC/CI, a separate
/// provider). Undocumented SPI, so — like the SkyLight lifecycle path — it lives in this experimental
/// module and is excluded from the public-API-only build (NFR-010 / D-008).
public struct DisplayServicesBrightnessProvider: Sendable {
    /// `(CGDirectDisplayID, float *out) -> 0 on success`.
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    /// `(CGDirectDisplayID, float value 0...1) -> 0 on success`.
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?

    public init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getFn = Self.lookup(handle, "DisplayServicesGetBrightness", as: GetFn.self)
        setFn = Self.lookup(handle, "DisplayServicesSetBrightness", as: SetFn.self)
    }

    private static func lookup<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    /// True if the brightness symbols resolved on this OS.
    public var isAvailable: Bool { getFn != nil && setFn != nil }

    /// The display's current brightness in 0...1, or nil if it can't be read (e.g. an external the
    /// framework doesn't drive — the caller should treat that as "brightness unsupported here").
    public func brightness(for id: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    /// Sets the display's brightness (clamped to 0...1). Returns false if unsupported or the call fails.
    @discardableResult
    public func setBrightness(_ value: Float, for id: CGDirectDisplayID) -> Bool {
        guard let setFn else { return false }
        return setFn(id, max(0, min(1, value))) == 0
    }
}
#endif
