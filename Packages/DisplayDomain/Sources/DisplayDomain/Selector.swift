import Foundation

/// A stable expression that resolves to one or more display records (PRD §12.3, AUT-002).
/// Ambiguity is an error for destructive mutations; read-only queries may return many.
public enum DisplaySelector: Hashable, Sendable, Codable {
    case id(DisplayRecordID)
    case alias(String)
    case tag(String)
    case name(String)
    case fingerprint(vendor: Int?, product: Int?, serial: String?)
    case role(Role)
    case state(Reachability)
    case topology(edge: TopologyEdge, of: String) // relativeTo another selector's alias/name

    public enum Role: String, Hashable, Sendable, Codable {
        case main
        case builtin
        case pointer
        case focus
    }

    public enum TopologyEdge: String, Hashable, Sendable, Codable {
        case leftOf
        case rightOf
        case above
        case below
    }

    /// Whether resolving this selector for a destructive operation requires a unique match.
    /// Set/role/state selectors may resolve to multiple displays and need explicit `--all`.
    public var isSetSelector: Bool {
        switch self {
        case .tag, .state: return true
        case .name, .fingerprint: return true // may be ambiguous → treated as a candidate set
        default: return false
        }
    }
}

public enum SelectorParseError: Error, Equatable, Sendable {
    case empty
    case unknownScheme(String)
    case malformed(String)
}

extension DisplaySelector {
    /// Parses the CLI/automation selector grammar, e.g. `id:disp_…`, `alias:DeskLeft`,
    /// `tag:studio`, `name:"LG HDR 4K"`, `vendor:610 product:12345`, `main`, `state:managedOffline`,
    /// `leftOf:alias:Center` (PRD §12.3).
    public static func parse(_ raw: String) throws -> DisplaySelector {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw SelectorParseError.empty }

        // Bare roles.
        switch text.lowercased() {
        case "main": return .role(.main)
        case "builtin", "built-in": return .role(.builtin)
        case "pointer": return .role(.pointer)
        case "focus", "focused": return .role(.focus)
        default: break
        }

        // Compound fingerprint form: "vendor:610 product:12345 serial:ABC".
        if text.contains("vendor:") || text.contains("product:") || text.contains("serial:") {
            return try parseFingerprint(text)
        }

        guard let colon = text.firstIndex(of: ":") else {
            throw SelectorParseError.malformed(text)
        }
        let scheme = String(text[text.startIndex..<colon]).lowercased()
        let value = unquote(String(text[text.index(after: colon)...]))

        switch scheme {
        case "id": return .id(DisplayRecordID(rawValue: value))
        case "alias": return .alias(value)
        case "tag": return .tag(value)
        case "name": return .name(value)
        case "state":
            guard let reach = Reachability(rawValue: value) else {
                throw SelectorParseError.malformed("state:\(value)")
            }
            return .state(reach)
        case "leftof": return .topology(edge: .leftOf, of: stripRelativeScheme(value))
        case "rightof": return .topology(edge: .rightOf, of: stripRelativeScheme(value))
        case "above": return .topology(edge: .above, of: stripRelativeScheme(value))
        case "below": return .topology(edge: .below, of: stripRelativeScheme(value))
        default:
            throw SelectorParseError.unknownScheme(scheme)
        }
    }

    private static func parseFingerprint(_ text: String) throws -> DisplaySelector {
        var vendor: Int?
        var product: Int?
        var serial: String?
        for token in text.split(separator: " ") {
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = unquote(String(parts[1]))
            switch key {
            case "vendor": vendor = Int(value)
            case "product": product = Int(value)
            case "serial": serial = value
            default: break
            }
        }
        if vendor == nil && product == nil && serial == nil {
            throw SelectorParseError.malformed(text)
        }
        return .fingerprint(vendor: vendor, product: product, serial: serial)
    }

    private static func stripRelativeScheme(_ value: String) -> String {
        // Accept either "alias:Center" or "Center" as the anchor reference.
        if let colon = value.firstIndex(of: ":") {
            return unquote(String(value[value.index(after: colon)...]))
        }
        return value
    }

    private static func unquote(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
    }
}
