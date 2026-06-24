import Foundation

/// A parsed EDID (Extended Display Identification Data) base block — the raw bytes a display reports
/// over DDC/IORegistry, decoded into structured fields. Pure value logic so it lives in the
/// cross-platform core and is exercised by `make test`; the macOS layer fetches the raw bytes.
///
/// Parsing is tolerant: a block with a bad header magic or shorter than 128 bytes returns nil, but a
/// well-formed block with garbled descriptors still parses (unknown descriptors become `.other`). The
/// checksum is computed and surfaced (`checksumValid`) but does not, by itself, reject the block.
public struct EDID: Hashable, Sendable, Codable {
    /// Three-letter PnP manufacturer id (e.g. "SAM", "DEL", "APP").
    public let manufacturerID: String
    /// 16-bit product/model code.
    public let productCode: Int
    /// 32-bit serial number (0 when not set in the numeric field).
    public let serialNumber: UInt32
    /// Week of manufacture (1...54), or nil when absent / the model-year flag (0xFF) is used.
    public let manufactureWeek: Int?
    /// Year of manufacture (or model year), or nil.
    public let manufactureYear: Int?
    public let edidVersion: Int
    public let edidRevision: Int
    /// Image size in centimetres from the basic display parameters, when defined.
    public let widthCm: Int?
    public let heightCm: Int?
    /// Display gamma (e.g. 2.2), when defined.
    public let gamma: Double?
    /// The four 18-byte descriptors (monitor name, serial text, range limits, detailed timing, …).
    public let descriptors: [Descriptor]
    /// Number of extension blocks that follow the base block.
    public let extensionCount: Int
    /// Whether the 128-byte base-block checksum is valid (sum mod 256 == 0).
    public let checksumValid: Bool

    public enum Descriptor: Hashable, Sendable, Codable {
        case monitorName(String)
        case serialText(String)
        case text(String)
        case rangeLimits
        /// A detailed timing — preferred resolution in active pixels.
        case detailedTiming(horizontalActive: Int, verticalActive: Int)
        case other(tag: Int)
    }

    /// The monitor name from a `0xFC` descriptor, if present.
    public var monitorName: String? {
        for case let .monitorName(name) in descriptors { return name }
        return nil
    }

    /// The text serial number from a `0xFF` descriptor, if present.
    public var serialText: String? {
        for case let .serialText(s) in descriptors { return s }
        return nil
    }

    /// The preferred (first detailed) timing's active resolution, if present.
    public var preferredResolution: (width: Int, height: Int)? {
        for case let .detailedTiming(h, v) in descriptors { return (h, v) }
        return nil
    }

    /// Parses an EDID base block (the first 128 bytes; extra extension bytes are tolerated). Returns nil
    /// if too short or the 8-byte header magic is wrong.
    public static func parse(_ bytes: [UInt8]) -> EDID? {
        guard bytes.count >= 128 else { return nil }
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard Array(bytes[0..<8]) == header else { return nil }

        let m = (Int(bytes[8]) << 8) | Int(bytes[9])
        let letters = [(m >> 10) & 0x1F, (m >> 5) & 0x1F, m & 0x1F]
        let manufacturerID = String(letters.map { Character(UnicodeScalar(UInt8(($0 & 0x1F) + 64))) })

        let productCode = Int(bytes[10]) | (Int(bytes[11]) << 8)
        let serial = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8)
            | (UInt32(bytes[14]) << 16) | (UInt32(bytes[15]) << 24)

        let weekByte = Int(bytes[16])
        let yearByte = Int(bytes[17])
        let week: Int? = (weekByte >= 1 && weekByte <= 54) ? weekByte : nil
        let year: Int? = yearByte > 0 ? yearByte + 1990 : nil

        let width = bytes[21] > 0 ? Int(bytes[21]) : nil
        let height = bytes[22] > 0 ? Int(bytes[22]) : nil
        let gamma: Double? = bytes[23] == 0xFF ? nil : (Double(bytes[23]) + 100) / 100

        var descriptors: [Descriptor] = []
        for offset in [54, 72, 90, 108] {
            descriptors.append(parseDescriptor(Array(bytes[offset..<offset + 18])))
        }

        let checksumValid = bytes[0..<128].reduce(0) { ($0 + Int($1)) } % 256 == 0

        return EDID(
            manufacturerID: manufacturerID, productCode: productCode, serialNumber: serial,
            manufactureWeek: week, manufactureYear: year,
            edidVersion: Int(bytes[18]), edidRevision: Int(bytes[19]),
            widthCm: width, heightCm: height, gamma: gamma,
            descriptors: descriptors, extensionCount: Int(bytes[126]), checksumValid: checksumValid
        )
    }

    private static func parseDescriptor(_ d: [UInt8]) -> Descriptor {
        // A display (non-timing) descriptor begins 00 00 00 <tag>; otherwise it's a detailed timing.
        if d[0] == 0 && d[1] == 0 && d[2] == 0 {
            let text = descriptorText(d)
            switch d[3] {
            case 0xFF: return .serialText(text)
            case 0xFC: return .monitorName(text)
            case 0xFE: return .text(text)
            case 0xFD: return .rangeLimits
            default: return .other(tag: Int(d[3]))
            }
        }
        let hActive = Int(d[2]) | ((Int(d[4]) >> 4) << 8)
        let vActive = Int(d[5]) | ((Int(d[7]) >> 4) << 8)
        return .detailedTiming(horizontalActive: hActive, verticalActive: vActive)
    }

    /// Text descriptors carry up to 13 ASCII bytes (offset 5...17), newline-terminated, space-padded.
    private static func descriptorText(_ d: [UInt8]) -> String {
        var chars: [Character] = []
        for b in d[5..<18] {
            if b == 0x0A { break }
            chars.append(Character(UnicodeScalar(b)))
        }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }

    /// A stable, deterministic, cross-platform hash of the raw EDID bytes (FNV-1a, hex) — for identity
    /// matching without a crypto dependency.
    public static func stableHash(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes {
            hash ^= UInt64(b)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}
