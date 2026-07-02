import Foundation

/// Negative cache for DDC feature probing, per display.
///
/// Probing a VCP feature a panel doesn't implement is the single most expensive DDC operation we
/// do: the strict-framing read retries several times with reply delays (~0.7s of I2C traffic) and
/// yields nothing — and without memory, every menu open re-pays that for every absent feature.
/// This tracker remembers what failed so refresh only re-reads features the panel actually has.
///
/// Two deliberate softenings keep it honest on flaky hardware (DDC fails transiently while a panel
/// wakes or another host uses the bus):
/// - a single failure is NOT "unsupported" — a feature is only skipped after `strikeLimit`
///   *consecutive* full-retry failures (any success resets its strikes);
/// - "unsupported" is never permanent — every `recheckInterval`-th admission of a skipped code is
///   allowed through as a probe, so a feature that appears later (panel firmware quirk, input
///   switch) is eventually rediscovered without waiting for a re-plug.
///
/// Pure and deterministic (counts, not clocks) so `make test` covers it; the app keeps one per
/// display record and drops it when the display disconnects.
public struct DDCProbeTracker: Hashable, Sendable {
    /// Consecutive full-retry failures before a code is negatively cached.
    public let strikeLimit: Int
    /// Every Nth skipped admission of an unsupported code re-probes it instead.
    public let recheckInterval: Int

    private var strikes: [UInt8: Int] = [:]
    private var unsupported: Set<UInt8> = []
    private var skipsSinceRecheck: [UInt8: Int] = [:]

    public init(strikeLimit: Int = 2, recheckInterval: Int = 8) {
        self.strikeLimit = max(1, strikeLimit)
        self.recheckInterval = max(1, recheckInterval)
    }

    /// Whether a refresh pass should spend I2C time probing `code` right now. Mutating: admitting a
    /// negatively-cached code counts toward its periodic recheck.
    public mutating func admitProbe(_ code: UInt8) -> Bool {
        guard unsupported.contains(code) else { return true }
        let skips = (skipsSinceRecheck[code] ?? 0) + 1
        if skips >= recheckInterval {
            skipsSinceRecheck[code] = 0
            return true
        }
        skipsSinceRecheck[code] = skips
        return false
    }

    /// A full-retry read of `code` returned nothing.
    public mutating func recordFailure(_ code: UInt8) {
        let count = (strikes[code] ?? 0) + 1
        strikes[code] = count
        if count >= strikeLimit { unsupported.insert(code) }
    }

    /// `code` answered — clear its strikes and any negative cache entry.
    public mutating func recordSuccess(_ code: UInt8) {
        strikes[code] = nil
        skipsSinceRecheck[code] = nil
        unsupported.remove(code)
    }

    /// Codes currently negatively cached (for diagnostics).
    public var unsupportedCodes: Set<UInt8> { unsupported }
}
