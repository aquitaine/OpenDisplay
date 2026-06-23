#if os(macOS)
import CoreGraphics
import Foundation
import IOKit

/// DDC/CI control of an external display over its private `IOAVService` I2C channel (Apple Silicon).
/// VCP feature codes follow the DDC/CI + MCCS spec: 0x10 brightness, 0x12 contrast, 0x62 audio
/// volume, 0x60 input source. The `IOAVService*` symbols are undocumented IOKit SPI resolved with
/// `dlsym` at runtime — so this links cleanly and is excluded from the public-API-only build, like
/// the SkyLight lifecycle and DisplayServices brightness paths. Serialized on its own actor and
/// using non-blocking sleeps for the DDC inter-message delays, so the slow I2C never touches the UI.
public actor ExternalDisplayDDC {
    /// Common VCP feature codes (Monitor Control Command Set).
    public enum Feature: UInt8, Sendable {
        case brightness = 0x10
        case contrast = 0x12
        case volume = 0x62
        case inputSource = 0x60
        case colorPreset = 0x14
    }

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias WriteFn = @convention(c) (AnyObject, UInt32, UInt32, UnsafePointer<UInt8>?, UInt32) -> Int32
    private typealias ReadFn = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, UInt32) -> Int32

    private let service: AnyObject
    private let writeFn: WriteFn
    private let readFn: ReadFn

    private static let i2cChip: UInt32 = 0x37    // DDC/CI 7-bit I2C address
    private static let i2cSource: UInt32 = 0x51  // host source address (the "dataAddress" arg)

    /// Binds to the external display's IOAVService, or fails if the display is the built-in, has no
    /// AV service, or the SPI is unavailable.
    public init?(displayID: CGDirectDisplayID) {
        guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let createPtr = dlsym(iokit, "IOAVServiceCreateWithService"),
              let writePtr = dlsym(iokit, "IOAVServiceWriteI2C"),
              let readPtr = dlsym(iokit, "IOAVServiceReadI2C")
        else { return nil }
        let create = unsafeBitCast(createPtr, to: CreateFn.self)
        writeFn = unsafeBitCast(writePtr, to: WriteFn.self)
        readFn = unsafeBitCast(readPtr, to: ReadFn.self)
        guard let svc = Self.avService(for: displayID) else { return nil }
        defer { IOObjectRelease(svc) }
        guard let av = create(kCFAllocatorDefault, svc) else { return nil }
        service = av.takeRetainedValue()
    }

    /// Reads a VCP feature: (current, max) in the display's native units (brightness/contrast 0...100
    /// on most panels), or nil if the display didn't answer.
    public func read(_ feature: Feature) async -> (current: Int, max: Int)? {
        let code = feature.rawValue
        let checksum = UInt8(0x6e ^ Int(Self.i2cSource) ^ 0x82 ^ 0x01) ^ code
        var request: [UInt8] = [0x82, 0x01, code, checksum]
        guard writeFn(service, Self.i2cChip, Self.i2cSource, &request, 4) == 0 else { return nil }
        try? await Task.sleep(nanoseconds: 60_000_000)
        var buffer = [UInt8](repeating: 0, count: 12)
        guard readFn(service, Self.i2cChip, Self.i2cSource, &buffer, 12) == 0,
              buffer[0] == 0x6e, buffer[2] == 0x02, buffer[3] == 0x00, buffer[4] == code
        else { return nil }  // buffer[3] is the DDC result code; non-zero = feature unsupported
        let maxValue = Int(buffer[6]) << 8 | Int(buffer[7])
        let current = Int(buffer[8]) << 8 | Int(buffer[9])
        return (current, maxValue)
    }

    /// Sets a VCP feature to a value in the display's native units. Returns false if the write failed.
    @discardableResult
    public func write(_ feature: Feature, _ value: Int) async -> Bool {
        let code = feature.rawValue
        let high = UInt8((value >> 8) & 0xff)
        let low = UInt8(value & 0xff)
        let checksum = UInt8(0x6e ^ Int(Self.i2cSource) ^ 0x84 ^ 0x03) ^ code ^ high ^ low
        var packet: [UInt8] = [0x84, 0x03, code, high, low, checksum]
        let ok = writeFn(service, Self.i2cChip, Self.i2cSource, &packet, 6) == 0
        try? await Task.sleep(nanoseconds: 50_000_000)
        return ok
    }

    /// Maps a `CGDirectDisplayID` to its external `IOAVService`. Exact for a single external; with
    /// several it matches by order among external displays (EDID matching is a later refinement).
    private static func avService(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var externals: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if location == "External" { externals.append(service) } else { IOObjectRelease(service) }
            service = IOIteratorNext(iterator)
        }
        guard !externals.isEmpty else { return nil }
        let index = externalDisplayIDs().firstIndex(of: displayID) ?? 0
        let chosen = externals[min(index, externals.count - 1)]
        for candidate in externals where candidate != chosen { IOObjectRelease(candidate) }
        return chosen
    }

    private static func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.sorted()
    }
}
#endif
