import Foundation

/// A DDC/CI power-mode command for an external display (VCP feature `0xD6`, MCCS "Power mode"). Lives
/// in the automation schema so the CLI, URL scheme, and menu all parse and label it the same way; the
/// macOS DDC layer maps `vcpValue` onto an `0xD6` write.
///
/// Only the three modes the product exposes are modeled. Per the MCCS spec, `0x04` is a DPMS-style
/// "off" the panel can usually wake from, while `0x05` is a harder power-down; many displays cannot be
/// woken back to `On` over DDC once powered off, so `On` is best-effort by nature.
public enum DDCPowerMode: String, Hashable, Sendable, Codable, CaseIterable {
    case on
    case standby
    case off

    /// The VCP `0xD6` value written to the display. `0x01` On, `0x04` Off (DPMS, typically wakeable),
    /// `0x05` Off (hard power-down).
    public var vcpValue: Int {
        switch self {
        case .on: return 0x01
        case .standby: return 0x04
        case .off: return 0x05
        }
    }

    /// Title-case label for menus and CLI output.
    public var label: String {
        switch self {
        case .on: return "On"
        case .standby: return "Standby"
        case .off: return "Off"
        }
    }

    /// Parses a user-supplied token (CLI argument or URL parameter), case- and whitespace-insensitive.
    /// Returns nil for anything outside the three known modes so callers can reject it cleanly rather
    /// than sending an arbitrary value to the panel.
    public init?(parsing token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "on": self = .on
        case "standby", "sleep", "dpms": self = .standby
        case "off": self = .off
        default: return nil
        }
    }

    /// The accepted tokens, for usage strings.
    public static let acceptedTokens = "on|standby|off"
}
