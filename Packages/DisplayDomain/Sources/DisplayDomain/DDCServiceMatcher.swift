import Foundation

/// Pure scoring that pairs a display with its DDC I2C service when a Mac drives several externals.
///
/// On Apple Silicon each external display exposes one `DCPAVServiceProxy` (the I2C channel DDC/CI
/// runs over), and the display node next to it (`AppleCLCD2`) carries the panel's EDID-derived
/// `ProductAttributes` (manufacturer, product id, serial). Matching the CG display to a service *by
/// enumeration order* silently controls the wrong monitor whenever IOKit and Core Graphics disagree
/// on ordering (dock re-plugs, mixed HDMI/DP, identical models) — so we score every candidate
/// against the CG display's vendor/product/serial and pick the best, falling back to order only
/// when no candidate carries identity attributes (some TVs/adapters strip them).
public enum DDCServiceMatcher {
    /// The identity attributes an IORegistry display-service candidate advertises
    /// (`DisplayAttributes` → `ProductAttributes` on the AppleCLCD2 node). All optional: real-world
    /// registries omit any of these, and a candidate with none simply scores zero.
    public struct Candidate: Hashable, Sendable {
        /// Numeric EDID vendor id (`LegacyManufacturerID`), e.g. Samsung = 0x4C2D.
        public var legacyManufacturerID: Int?
        /// Three-letter PnP id (`ManufacturerID`), e.g. "SAM" — converted for scoring when the
        /// numeric field is missing.
        public var manufacturerID: String?
        /// EDID product code (`ProductID`).
        public var productID: Int?
        /// EDID numeric serial (`SerialNumber`). Zero means "not set" and never matches.
        public var serialNumber: Int?

        public init(legacyManufacturerID: Int? = nil, manufacturerID: String? = nil,
                    productID: Int? = nil, serialNumber: Int? = nil) {
            self.legacyManufacturerID = legacyManufacturerID
            self.manufacturerID = manufacturerID
            self.productID = productID
            self.serialNumber = serialNumber
        }
    }

    /// The CG-side identity of the display we want a service for (`CGDisplayVendorNumber` /
    /// `CGDisplayModelNumber` / `CGDisplaySerialNumber`). Zeros are treated as "unknown".
    public struct Target: Hashable, Sendable {
        public var vendorNumber: Int
        public var productNumber: Int
        public var serialNumber: Int

        public init(vendorNumber: Int, productNumber: Int, serialNumber: Int) {
            self.vendorNumber = vendorNumber
            self.productNumber = productNumber
            self.serialNumber = serialNumber
        }
    }

    /// EDID PnP id → numeric vendor: three letters A–Z packed as 5-bit values (A = 1) into a
    /// big-endian 16-bit word, e.g. "SAM" → 0x4C2D, "GSM" → 0x1E6D. Nil for anything that isn't
    /// exactly three ASCII letters — matching on a malformed id would be a false positive.
    public static func vendorNumber(fromPNP id: String) -> Int? {
        let letters = Array(id.uppercased().unicodeScalars)
        guard letters.count == 3, letters.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return letters.reduce(0) { ($0 << 5) | (Int($1.value) - 64) }
    }

    /// Match strength of one candidate: serial (4) dominates product (2) dominates vendor (1), so a
    /// serial match can never be outvoted by the weaker signals — mirroring how EDID identity is
    /// trusted elsewhere (`IdentityScorer`). A field only scores when *both* sides know it and it's
    /// non-zero (CG reports 0 for unknown; EDID serials of 0 are "not programmed").
    public static func score(_ candidate: Candidate, against target: Target) -> Int {
        var total = 0
        let candidateVendor = candidate.legacyManufacturerID
            ?? candidate.manufacturerID.flatMap(vendorNumber(fromPNP:))
        if let vendor = candidateVendor, vendor != 0, vendor == target.vendorNumber { total += 1 }
        if let product = candidate.productID, product != 0, product == target.productNumber { total += 2 }
        if let serial = candidate.serialNumber, serial != 0, serial == target.serialNumber { total += 4 }
        return total
    }

    /// Picks the candidate index to bind. Highest positive score wins; when nothing scores (no
    /// attributes anywhere, or a genuinely foreign display) or the best score is tied — e.g. two
    /// *identical* monitors with unprogrammed serials — prefer `fallbackIndex` (the order-based
    /// guess) if it's among the tied best, else the first best. Always returns a valid index into
    /// a non-empty array; nil only when `candidates` is empty.
    public static func bestIndex(of candidates: [Candidate?], against target: Target,
                                 fallbackIndex: Int) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let clampedFallback = min(max(fallbackIndex, 0), candidates.count - 1)
        let scores = candidates.map { $0.map { score($0, against: target) } ?? 0 }
        guard let best = scores.max(), best > 0 else { return clampedFallback }
        let winners = scores.indices.filter { scores[$0] == best }
        return winners.contains(clampedFallback) ? clampedFallback : winners[0]
    }
}
