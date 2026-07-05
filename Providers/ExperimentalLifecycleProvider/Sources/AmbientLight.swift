#if os(macOS)
import CoreFoundation
import Foundation

/// Best-effort reader of the Mac's ambient light sensor, via the `IOHIDEventSystemClient` SPI
/// (exported by IOKit but not in public headers — resolved with `dlsym` like the rest of this
/// module). This is what lets Adaptive Display keep true light-driven brightness when the
/// built-in display is turned OFF but the lid is open (Mac-keyboard-plus-external setups):
/// macOS stops driving any panel from the sensor, but the sensor itself keeps reporting.
///
/// Stateless: each call builds the client, matches the AppleVendor ALS usage (page 0xFF00,
/// usage 4), and copies one event — a fraction of a millisecond of IPC, called at the adaptive
/// loop's 5s cadence. Any failure (lid closed, no sensor, SPI moved) returns nil and the caller
/// falls back to its schedule curve.
public struct AmbientLightReader: Sendable {
    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, AnyObject?, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private let create: ClientCreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?

    private static let eventTypeALS: Int64 = 12                 // kIOHIDEventTypeAmbientLightSensor
    private static let fieldALSLevel = Int32(12 << 16)          // …FieldAmbientLightSensorLevel (lux)

    public init() {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let iokit, let ptr = dlsym(iokit, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        create = sym("IOHIDEventSystemClientCreate", as: ClientCreateFn.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        getFloat = sym("IOHIDEventGetFloatValue", as: GetFloatFn.self)
    }

    /// The current ambient light in lux, or nil when the sensor can't be read (covered lid, no
    /// sensor, unavailable SPI). 0 lux is a legitimate reading (dark room), not a failure.
    public func lux() -> Double? {
        guard let create, let setMatching, let copyServices, let copyEvent, let getFloat,
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject],
              let sensor = services.first else { return nil }
        guard let event = copyEvent(sensor, Self.eventTypeALS, nil, 0)?.takeRetainedValue() else {
            return nil
        }
        let value = getFloat(event, Self.fieldALSLevel)
        return value.isFinite && value >= 0 ? value : nil
    }
}
#endif
