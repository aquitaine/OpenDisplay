#if os(macOS)
import CoreGraphics
import DisplayDomain
import Foundation
import IOKit

/// Reads the raw EDID blob for a display from IORegistry (public IOKit — no private SPI). On Apple
/// Silicon the EDID lives on display nodes under the DCP; we collect every EDID-shaped property and
/// match it to the requested display by its EDID **product code** (`CGDisplayModelNumber`), which is a
/// reliable disambiguator even with several externals; we fall back to built-in/order when no match.
public enum EDIDReader {
    /// Best-effort raw EDID bytes for `cgID`, or nil if none is exposed for it.
    public static func rawEDID(for cgID: CGDirectDisplayID) -> [UInt8]? {
        let candidates = allEDIDs()
        guard !candidates.isEmpty else { return nil }

        // Prefer an exact product-code match (most distinctive identity field).
        let wantProduct = Int(CGDisplayModelNumber(cgID))
        if wantProduct != 0, wantProduct != 0xFFFF_FFFF {
            if let hit = candidates.first(where: { EDID.parse($0)?.productCode == wantProduct }) {
                return hit
            }
        }
        // Fall back: a single candidate is unambiguous. Otherwise honour built-in vs external —
        // the built-in panel's EDID carries Apple's PNP id ("APP"), so an external request must
        // skip those (tree order puts the built-in first, which would hand back the laptop
        // panel's identity); a built-in request prefers them. Tree order breaks remaining ties.
        if candidates.count == 1 { return candidates[0] }
        let wantBuiltIn = CGDisplayIsBuiltin(cgID) != 0
        return candidates.first { (EDID.parse($0)?.manufacturerID == "APP") == wantBuiltIn }
            ?? candidates.first
    }

    /// Every EDID-shaped Data property found by walking the whole IORegistry service plane (the EDID
    /// node's class varies across Apple-Silicon macOS versions, so a recursive walk is more robust than
    /// guessing service classes), deduplicated in tree order.
    private static func allEDIDs() -> [[UInt8]] {
        var iter = io_iterator_t()
        guard IORegistryCreateIterator(
            kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var seen: Set<[UInt8]> = []
        var result: [[UInt8]] = []
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let edid = edidProperty(entry), !seen.contains(edid) {
                seen.insert(edid); result.append(edid)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return result
    }

    private static func edidProperty(_ entry: io_registry_entry_t) -> [UInt8]? {
        for key in ["EDID", "IODisplayEDID"] {
            guard let prop = IORegistryEntryCreateCFProperty(
                entry, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() else { continue }
            if let data = prop as? Data, data.count >= 128 { return [UInt8](data) }
        }
        return nil
    }
}
#endif
