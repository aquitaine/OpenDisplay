#if os(macOS)
import CoreGraphics
import DisplayDomain
import Foundation
import IOKit

/// DDC/CI control of an external display over its private `IOAVService` I2C channel (Apple Silicon).
/// VCP feature codes follow the DDC/CI + MCCS spec: 0x10 brightness, 0x12 contrast, 0x62 audio
/// volume, 0x60 input source. The `IOAVService*` symbols are undocumented IOKit SPI resolved with
/// `dlsym` at runtime — so this links cleanly and is excluded from the public-API-only build, like
/// the SkyLight lifecycle and DisplayServices brightness paths. Runs on its own actor with a FIFO
/// bus turnstile (`lockBus`) making each multi-step transaction exclusive — the actor alone is NOT
/// enough, since it is reentrant at the awaits inside a transaction — and uses non-blocking sleeps
/// for the DDC inter-message delays, so the slow I2C never touches the UI.
public actor ExternalDisplayDDC {
    /// Common VCP feature codes (Monitor Control Command Set). Any other code a panel implements is
    /// reachable through the raw `read(vcp:)` / `write(vcp:_:)` overloads.
    public enum Feature: UInt8, Sendable {
        case brightness = 0x10
        case contrast = 0x12
        case volume = 0x62
        case inputSource = 0x60
        case colorPreset = 0x14
        case redGain = 0x16
        case greenGain = 0x18
        case blueGain = 0x1A
        case sharpness = 0x87
        /// Audio mute. Discrete per MCCS: 1 = muted, 2 = unmuted.
        case audioMute = 0x8D
        /// Power mode (DPM). Values: 0x01 On, 0x04 Off (DPMS, usually wakeable), 0x05 Off (hard).
        case power = 0xD6
    }

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias WriteFn = @convention(c) (AnyObject, UInt32, UInt32, UnsafePointer<UInt8>?, UInt32) -> Int32
    private typealias ReadFn = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutablePointer<UInt8>?, UInt32) -> Int32

    private let service: AnyObject
    private let writeFn: WriteFn
    private let readFn: ReadFn

    private static let i2cChip: UInt32 = 0x37    // DDC/CI 7-bit I2C address
    private static let i2cSource: UInt32 = 0x51  // host source address (the "dataAddress" arg)

    // DDC/CI reads are flaky and easily desynchronized (a previous reply can linger in the panel's
    // buffer). Retry a few times, validate strictly, and give the panel time to prepare each reply.
    // The first attempt uses the shorter delay (proven sufficient on healthy panels); retries wait
    // longer since a slow panel is the main reason a first attempt fails.
    private static let readRetries = 5
    private static let readReplyFirstNanos: UInt64 = 60_000_000  // 60ms on the first attempt
    private static let readReplyNanos: UInt64 = 100_000_000      // 100ms on retries

    /// Minimum quiet gap between DDC transactions on the same panel. Enforced by *pacing* (sleep
    /// only the unelapsed remainder before the next transaction) rather than a blanket sleep after
    /// every operation — so a lone write returns as soon as the I2C call does, while back-to-back
    /// operations still never hit the panel faster than it can digest (the desync trigger).
    private static let interTransactionGapNanos: UInt64 = 50_000_000
    private var lastTransactionUptime: UInt64 = 0

    /// Waits out the inter-transaction gap since the last bus operation. Loops rather than sleeping
    /// once: actors are reentrant during `Task.sleep`, so another task may transact while we sleep,
    /// moving the deadline — a single fixed sleep would then hit the bus too early.
    private func paceBus() async {
        while lastTransactionUptime != 0 {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- lastTransactionUptime
            if elapsed >= Self.interTransactionGapNanos { return }
            try? await Task.sleep(nanoseconds: Self.interTransactionGapNanos - elapsed)
        }
    }

    private func markTransaction() {
        lastTransactionUptime = DispatchTime.now().uptimeNanoseconds
    }

    // The actor alone does NOT make a DDC transaction atomic: a read suspends between writing the
    // request and reading the reply, and Swift actors are reentrant at suspension points — so a
    // coalesced slider write could land on the bus inside another read's reply window, invalidating
    // the pending reply (and reproducing the rapid-fire traffic that desyncs panels). This FIFO
    // turnstile makes each transaction exclusive: lock around request→delay→reply, not just around
    // individual I2C calls.
    private var busLocked = false
    private var busWaiters: [CheckedContinuation<Void, Never>] = []

    private func lockBus() async {
        if !busLocked { busLocked = true; return }
        await withCheckedContinuation { busWaiters.append($0) }
    }

    private func unlockBus() {
        if busWaiters.isEmpty { busLocked = false } else { busWaiters.removeFirst().resume() }
    }

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
    /// on most panels), or nil if the display never answered with a well-formed reply.
    /// See `read(vcp:)` for the framing/validation story.
    public func read(_ feature: Feature) async -> (current: Int, max: Int)? {
        await read(vcp: feature.rawValue)
    }

    /// Raw-VCP variant of `read(_:)` for codes outside the `Feature` enum — panels implement far
    /// more of MCCS than we name (KVM toggles, OSD language, colour temperature…), and the CLI/UI
    /// shouldn't need a source change to reach them.
    ///
    /// Reads a WIDE buffer and scans it for the reply frame instead of demanding it at offset 0:
    /// mildly desynchronized scalers commonly return the valid frame prefixed by a few stale bytes
    /// (observed live on a Samsung S34J55x — `… d8 6c 6f | 6e 88 02 00 12 …`), and an offset-0-only
    /// check reads those panels as "unsupported" forever. A scanned match must echo *our* VCP code
    /// AND carry a valid DDC/CI reply checksum (`0x50 ^ frame bytes` — verified against captured
    /// hardware replies), so stale garbage can't masquerade as a value.
    public func read(vcp code: UInt8) async -> (current: Int, max: Int)? {
        for attempt in 0..<Self.readRetries {
            await lockBus()
            let value = await readAttempt(code, attempt: attempt)
            unlockBus()
            if let value { return value }
        }
        return nil
    }

    /// One bus-exclusive Get-VCP transaction: request → reply delay → wide read → frame scan.
    /// Caller holds the bus lock, so nothing can interleave between the request and its reply.
    private func readAttempt(_ code: UInt8, attempt: Int) async -> (current: Int, max: Int)? {
        let checksum = UInt8(0x6e ^ Int(Self.i2cSource) ^ 0x82 ^ 0x01) ^ code
        await paceBus()
        var request: [UInt8] = [0x82, 0x01, code, checksum]
        let wrote = writeFn(service, Self.i2cChip, Self.i2cSource, &request, 4) == 0
        markTransaction()
        guard wrote else { return nil }  // paceBus() spaces the retry
        try? await Task.sleep(nanoseconds: attempt == 0 ? Self.readReplyFirstNanos : Self.readReplyNanos)
        var buffer = [UInt8](repeating: 0, count: Self.readWindow)
        let readOK = readFn(service, Self.i2cChip, Self.i2cSource, &buffer, UInt32(Self.readWindow)) == 0
        markTransaction()
        guard readOK else { return nil }
        return Self.scanReply(in: buffer, vcp: code)
    }

    /// Bytes fetched per Get-VCP reply read. The frame itself is 11; the extra window is what lets
    /// `scanReply` recover replies that arrive behind stale prefix bytes. Reading beyond the reply
    /// is harmless on I2C (the device pads) — the capabilities path has always read 64 this way.
    private static let readWindow = 48

    /// Finds a well-formed Get-VCP reply for `code` anywhere in `buffer`: source `0x6e`, length
    /// `0x88`, Get-reply opcode `0x02`, result OK, echoed code, and a valid reply checksum
    /// (XOR of `0x50` and the 10 frame bytes must equal the 11th).
    ///
    /// Falls back to the structural offset-0 check WITHOUT the length/checksum requirements when no
    /// checksummed frame is found: some panels ship malformed length bytes or wrong checksums, and
    /// those exact replies were accepted by every previous version of this reader — the stricter
    /// validation must only ever ADD recoveries, never regress a panel that used to work.
    private static func scanReply(in buffer: [UInt8], vcp code: UInt8) -> (current: Int, max: Int)? {
        guard buffer.count >= 11 else { return nil }
        for offset in 0...(buffer.count - 11) {
            guard buffer[offset] == 0x6e, buffer[offset + 1] == 0x88, buffer[offset + 2] == 0x02,
                  buffer[offset + 3] == 0x00, buffer[offset + 4] == code else { continue }
            let frame = buffer[offset..<(offset + 10)]
            guard frame.reduce(0x50 as UInt8, ^) == buffer[offset + 10] else { continue }
            let maxValue = Int(buffer[offset + 6]) << 8 | Int(buffer[offset + 7])
            let current = Int(buffer[offset + 8]) << 8 | Int(buffer[offset + 9])
            return (current, maxValue)
        }
        // Legacy-compat fallback: exactly the old validation, offset 0 only.
        if buffer[0] == 0x6e, buffer[2] == 0x02, buffer[3] == 0x00, buffer[4] == code {
            return (Int(buffer[8]) << 8 | Int(buffer[9]), Int(buffer[6]) << 8 | Int(buffer[7]))
        }
        return nil
    }

    /// Sets a VCP feature to a value in the display's native units. Returns false if the write failed.
    @discardableResult
    public func write(_ feature: Feature, _ value: Int) async -> Bool {
        await write(vcp: feature.rawValue, value)
    }

    /// Raw-VCP variant of `write(_:_:)` — see `read(vcp:)`. Returns as soon as the I2C call does;
    /// the mandatory settle time before the *next* transaction is enforced by pacing, not by
    /// sleeping here, so a single slider tick doesn't pay 50ms of dead latency.
    @discardableResult
    public func write(vcp code: UInt8, _ value: Int) async -> Bool {
        let high = UInt8((value >> 8) & 0xff)
        let low = UInt8(value & 0xff)
        let checksum = UInt8(0x6e ^ Int(Self.i2cSource) ^ 0x84 ^ 0x03) ^ code ^ high ^ low
        var packet: [UInt8] = [0x84, 0x03, code, high, low, checksum]
        await lockBus()
        await paceBus()
        let ok = writeFn(service, Self.i2cChip, Self.i2cSource, &packet, 6) == 0
        markTransaction()
        unlockBus()
        return ok
    }

    /// Reads the display's DDC/CI capabilities string (the response to VCP `0xF3`, MCCS spec) by
    /// requesting it in chunks and concatenating the replies until the display returns an empty chunk.
    /// Returns nil if the display doesn't answer. Best-effort: a NAK or a malformed reply just ends the
    /// read with whatever was gathered so far. Parse the result with `DDCCapabilities.parse`.
    ///
    /// ⚠️ This long multi-chunk read can DESYNCHRONIZE DDC/CI on some panels (Samsung S34J55x), leaving
    /// the panel replaying a stale reply buffer so later reads return garbage and writes are ignored
    /// until a power-cycle. Probed live on a wedged S34J55x: the scaler cycles a ~192-byte ring of old
    /// capabilities-reply bytes, drops new replies, and neither read-draining nor a display sleep/wake
    /// clears it — only the panel's own power switch does. Treat it as an explicit, diagnostic-only
    /// call (CLI `ddc … caps`) — never run it on the normal control-refresh path.
    public func readCapabilitiesString() async -> String? {
        // Hold the bus for the whole multi-chunk sequence: an interleaved transaction between
        // chunks breaks the offset continuation and is the likeliest wedge trigger.
        await lockBus()
        let result = await readCapabilitiesLocked()
        unlockBus()
        return result
    }

    private func readCapabilitiesLocked() async -> String? {
        var bytes: [UInt8] = []
        var offset: UInt16 = 0
        // Safety cap: 96 chunks × ~32 bytes ≈ 3 KB, far beyond any real capabilities string.
        for _ in 0..<96 {
            let high = UInt8(offset >> 8)
            let low = UInt8(offset & 0xff)
            // Capabilities Request: length 0x83 (3 data bytes), opcode 0xF3, 16-bit offset.
            let checksum = UInt8(0x6e ^ Int(Self.i2cSource) ^ 0x83 ^ 0xf3) ^ high ^ low
            var request: [UInt8] = [0x83, 0xf3, high, low, checksum]
            await paceBus()
            let wrote = writeFn(service, Self.i2cChip, Self.i2cSource, &request, 5) == 0
            markTransaction()
            guard wrote else { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
            var buffer = [UInt8](repeating: 0, count: 64)
            let readOK = readFn(service, Self.i2cChip, Self.i2cSource, &buffer, 64) == 0
            markTransaction()
            guard readOK,
                  buffer[0] == 0x6e, buffer[2] == 0xe3 else { break }  // 0xE3 = Capabilities Reply
            let length = Int(buffer[1] & 0x7f)
            // length covers opcode (0xE3) + 2 offset bytes + the data; fewer means a malformed reply.
            guard length >= 3 else { break }
            let replyOffset = UInt16(buffer[3]) << 8 | UInt16(buffer[4])
            guard replyOffset == offset else { break }  // out of sync — stop
            let dataLen = length - 3
            if dataLen == 0 { break }  // empty chunk = end of string
            let end = min(5 + dataLen, buffer.count)
            bytes.append(contentsOf: buffer[5..<end])
            offset += UInt16(end - 5)
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .ascii) ?? String(bytes: bytes, encoding: .utf8)
    }

    /// Maps a `CGDirectDisplayID` to its external `IOAVService` by **identity**, not order.
    ///
    /// One recursive IORegistry walk collects every external `DCPAVServiceProxy` together with the
    /// `ProductAttributes` (manufacturer / product id / serial) of the display node most recently
    /// seen before it — on Apple Silicon the panel's `AppleCLCD2` node precedes its AV proxy in
    /// service-plane order, so "most recent display attributes" is that proxy's panel. Each
    /// candidate is then scored against the CG display's vendor/model/serial
    /// (`DDCServiceMatcher`), which keeps DDC bound to the *right* monitor across dock re-plugs,
    /// mixed HDMI/DP topologies, and IOKit-vs-CG ordering disagreements. Candidates without
    /// attributes score zero and the old order-based choice remains the fallback, so nothing that
    /// worked before stops working.
    private static func avService(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(
            kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var externals: [io_service_t] = []
        var candidates: [DDCServiceMatcher.Candidate?] = []
        // Up to two walks: IOKit invalidates a live iterator when the registry mutates mid-walk
        // (exactly what happens during display hotplug, which is when we run), and an invalidated
        // iterator just stops early — silently truncating the candidate list. Retry once from a
        // reset iterator rather than binding a display to a partial view of the registry.
        for _ in 0..<2 {
            var pendingAttributes: DDCServiceMatcher.Candidate?
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                if let attributes = productAttributes(entry) {
                    pendingAttributes = attributes
                } else if IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0 {
                    let location = IORegistryEntryCreateCFProperty(
                        entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                    if location == "External" {
                        externals.append(entry)
                        candidates.append(pendingAttributes)
                        pendingAttributes = nil
                        entry = IOIteratorNext(iterator)
                        continue  // kept — don't release
                    }
                    // A non-external proxy (the built-in's "Embedded") still closes out its
                    // display's subtree. Without this, the built-in's Apple attributes would leak
                    // onto the next attribute-less external and could out-score the real match.
                    pendingAttributes = nil
                }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            if IOIteratorIsValid(iterator) != 0 { break }
            for kept in externals { IOObjectRelease(kept) }
            externals.removeAll()
            candidates.removeAll()
            IOIteratorReset(iterator)
        }
        guard !externals.isEmpty else { return nil }

        let target = DDCServiceMatcher.Target(
            vendorNumber: Int(CGDisplayVendorNumber(displayID)),
            productNumber: Int(CGDisplayModelNumber(displayID)),
            serialNumber: Int(CGDisplaySerialNumber(displayID)))
        let orderIndex = externalDisplayIDs().firstIndex(of: displayID) ?? 0
        let index = DDCServiceMatcher.bestIndex(of: candidates, against: target,
                                                fallbackIndex: orderIndex) ?? 0
        let chosen = externals[index]
        for candidate in externals where candidate != chosen { IOObjectRelease(candidate) }
        return chosen
    }

    /// The EDID-derived identity a display-service node advertises (`DisplayAttributes` →
    /// `ProductAttributes` on e.g. `AppleCLCD2`), or nil for nodes that aren't displays. Field
    /// names are the IOKit-published ones; every one is optional in the wild.
    private static func productAttributes(_ entry: io_registry_entry_t) -> DDCServiceMatcher.Candidate? {
        guard let raw = IORegistryEntryCreateCFProperty(
            entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let attributes = raw as? [String: Any],
              let product = attributes["ProductAttributes"] as? [String: Any]
        else { return nil }
        return DDCServiceMatcher.Candidate(
            legacyManufacturerID: product["LegacyManufacturerID"] as? Int,
            manufacturerID: product["ManufacturerID"] as? String,
            productID: product["ProductID"] as? Int,
            serialNumber: product["SerialNumber"] as? Int)
    }

    private static func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.sorted()
    }
}
#endif
