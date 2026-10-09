import Foundation

/// The capabilities a display advertises in its DDC/CI "capabilities string" (the response to a VCP
/// `0xF3` request, MCCS spec). Used to make the controls honest: only offer features a panel actually
/// supports, and (for discrete features) only the values it lists. Pure value type so the parser lives
/// in the cross-platform core and is exercised by `make test`; the macOS DDC layer fetches the string.
///
/// The capabilities string looks like
/// `(prot(monitor)type(lcd)model(X)cmds(01 02 03 0C E3 F3)vcp(10 12 14(05 08 0B) 60(01 03 11) D6(01 04 05))mccs_ver(2.1))`.
/// Only the `vcp(...)` block matters here: a space-separated list of VCP feature codes, each optionally
/// followed by a parenthesised list of the discrete values it accepts.
public struct DDCCapabilities: Hashable, Sendable, Codable {
    /// Every VCP feature code the display advertises.
    public let supportedVCPCodes: Set<UInt8>
    /// For discrete features, the accepted values, keyed by VCP code.
    public let discreteValues: [UInt8: [Int]]
    /// The original capabilities string, retained verbatim for display/debugging.
    public let raw: String

    public init(supportedVCPCodes: Set<UInt8>, discreteValues: [UInt8: [Int]], raw: String) {
        self.supportedVCPCodes = supportedVCPCodes
        self.discreteValues = discreteValues
        self.raw = raw
    }

    /// Whether the display advertises this VCP feature code.
    public func supports(_ code: UInt8) -> Bool { supportedVCPCodes.contains(code) }

    /// The accepted discrete values for a feature, or nil if the display didn't enumerate any (a
    /// continuous control like brightness, or simply absent).
    public func values(for code: UInt8) -> [Int]? { discreteValues[code] }

    /// The highest VCP `0x14` (Select Color Preset) code MCCS 2.2 defines: `0x01`…`0x0C` are sRGB,
    /// display native, 4000K, 5000K, 6500K, 7500K, 8200K, 9300K, 10000K, 11500K, User 1, User 2.
    /// 0x14 is a **non-continuous** feature, so the "max" field of its Get-VCP reply is meaningless —
    /// and some panels (e.g. LG HDR WQHD+) report 0xFFFF there. A `1...max` fallback built from that
    /// reply would be a 65,535-item menu, so the colour-preset fallback is clamped to this ceiling.
    public static let colorPresetCodeCeiling = 0x0C

    /// The values a picker should offer for a feature. For a **non-continuous** code (e.g. `0x14`
    /// Select Color Preset, `0x60` Input Source) the only values the panel honors are the discrete ones
    /// it advertised — offering a contiguous `1...max` range instead makes most selections silent no-ops,
    /// because the monitor ignores codes it never listed. So: prefer the advertised discrete values; fall
    /// back to `1...fallbackMax` only when capabilities are unavailable (`caps == nil`) or the panel
    /// didn't enumerate this code. `caps` is optional so callers can pass a possibly-unread cache.
    ///
    /// For `0x14` the fallback is clamped to `colorPresetCodeCeiling`, because the reported max is not
    /// a real bound for a non-continuous feature (see there). `current` — the panel's live value, when
    /// known — is always included (sorted, de-duplicated), so a picker's label and selection stay
    /// truthful even when the panel sits on a code outside the offered set (e.g. a vendor-specific 0xFF).
    public static func offeredValues(
        _ caps: DDCCapabilities?, for code: UInt8, fallbackMax: Int, current: Int? = nil
    ) -> [Int] {
        var values: [Int]
        if let advertised = caps?.values(for: code), !advertised.isEmpty {
            values = advertised
        } else {
            let upper = code == 0x14 ? min(fallbackMax, colorPresetCodeCeiling) : fallbackMax
            values = upper >= 1 ? Array(1...upper) : []
        }
        if let current, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    /// Parses an MCCS capabilities string. Returns nil when there's no balanced `vcp(...)` block to read
    /// (or it lists no codes) — callers then fall back to offering everything. Within the block it's
    /// best-effort and tolerant: a token it can't make sense of is skipped, never fatal.
    public static func parse(_ string: String) -> DDCCapabilities? {
        // Hex codes are case-insensitive and the `vcp` label may be upper/lower — parse lowercased.
        guard let vcp = balancedGroup(after: "vcp", in: Array(string.lowercased())) else { return nil }
        var codes: Set<UInt8> = []
        var discrete: [UInt8: [Int]] = [:]
        var i = 0
        while i < vcp.count {
            if vcp[i].isWhitespace { i += 1; continue }
            // Read a hex feature code.
            var hex = ""
            while i < vcp.count, vcp[i].isHexDigit { hex.append(vcp[i]); i += 1 }
            guard !hex.isEmpty, let code = UInt8(hex, radix: 16) else {
                if i < vcp.count { i += 1 }  // skip a stray char to make progress
                continue
            }
            codes.insert(code)
            // Optional discrete-value group: `(v1 v2 …)`.
            if i < vcp.count, vcp[i] == "(" {
                i += 1
                var values: [Int] = []
                var valHex = ""
                while i < vcp.count, vcp[i] != ")" {
                    if vcp[i].isHexDigit {
                        valHex.append(vcp[i])
                    } else if let v = Int(valHex, radix: 16) {
                        values.append(v); valHex = ""
                    } else {
                        valHex = ""
                    }
                    i += 1
                }
                if let v = Int(valHex, radix: 16) { values.append(v) }
                if i < vcp.count, vcp[i] == ")" { i += 1 }
                if !values.isEmpty { discrete[code] = values }
            }
        }
        guard !codes.isEmpty else { return nil }
        return DDCCapabilities(supportedVCPCodes: codes, discreteValues: discrete, raw: string)
    }

    /// The characters inside `label(...)`'s balanced parentheses, or nil if absent/unbalanced.
    private static func balancedGroup(after label: String, in chars: [Character]) -> [Character]? {
        let needle = Array(label + "(")
        guard !needle.isEmpty, chars.count >= needle.count else { return nil }
        var start = -1
        for i in 0...(chars.count - needle.count) where Array(chars[i..<i + needle.count]) == needle {
            start = i + needle.count
            break
        }
        guard start >= 0 else { return nil }
        var depth = 1
        var end = start
        while end < chars.count {
            if chars[end] == "(" { depth += 1 }
            else if chars[end] == ")" { depth -= 1; if depth == 0 { break } }
            end += 1
        }
        guard depth == 0 else { return nil }  // unbalanced
        return Array(chars[start..<end])
    }
}
