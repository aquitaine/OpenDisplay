#if os(macOS)
import Foundation
import ObjectiveC

/// Best-effort reader of macOS Night Shift's live on/off state, via the private CoreBrightness
/// framework's `CBBlueLightClient` — so Adaptive Display's evening warmth can follow the exact
/// schedule/toggles the user already maintains in System Settings, instead of a second clock.
///
/// Resolved entirely at runtime (dlopen + `NSClassFromString` + a responds-check + an IMP call),
/// like the DisplayServices and SkyLight wrappers in this module, so nothing links against the
/// private framework and every failure degrades to `nil` — the caller then falls back to its
/// fixed schedule. Excluded from the public-API-only build with the rest of this provider.
///
/// Deliberate fragility containment: `getBlueLightStatus:` fills a caller-provided struct whose
/// TAIL has grown across macOS releases. We never declare that struct. We hand the call a zeroed
/// buffer far larger than any known layout and read only byte 0 — the `active` BOOL, whose offset
/// has been stable since Night Shift shipped (10.12.4). If Apple ever moves even that, the worst
/// case is a wrong warm/cool phase, never memory corruption — and the schedule fallback remains
/// the documented behavior.
public struct NightShiftStatusReader: Sendable {
    /// `getBlueLightStatus:` fills ~40–80 bytes across known macOS versions; 128 absorbs growth.
    private static let statusBufferSize = 128

    /// One process-wide `CBBlueLightClient`: constructing it opens an XPC connection to
    /// corebrightnessd, so building (and tearing down) a fresh one per 5s adaptive tick would
    /// churn connections forever. `static let` gives thread-safe lazy init; the status call itself
    /// is an ordinary XPC round-trip and safe from any thread (`nonisolated(unsafe)` records that
    /// judgement, since the private class can't be marked Sendable).
    private nonisolated(unsafe) static let client: NSObject? = {
        // dlopen first: NSClassFromString alone can't find the class unless something already
        // loaded CoreBrightness into this process.
        guard dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY
        ) != nil else { return nil }
        guard let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            return nil
        }
        return clientClass.init()
    }()

    public init() {}

    /// Whether Night Shift is currently active, or nil if the private client is unavailable or
    /// the call fails in any way. Cheap enough to call once per adaptive tick (5s).
    public func isActive() -> Bool? {
        guard let client = Self.client else { return nil }
        let selector = Selector(("getBlueLightStatus:"))
        guard client.responds(to: selector), let method = client.method(for: selector) else {
            return nil
        }
        typealias GetStatusFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> ObjCBool
        let getStatus = unsafeBitCast(method, to: GetStatusFn.self)
        var buffer = [UInt8](repeating: 0, count: Self.statusBufferSize)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return getStatus(client, selector, base).boolValue
        }
        guard ok else { return nil }
        return buffer[0] != 0  // offset 0 = `active` BOOL, stable since 10.12.4
    }
}
#endif
