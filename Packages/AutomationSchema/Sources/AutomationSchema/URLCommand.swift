import DisplayDomain
import Foundation

/// A command parsed from an `opendisplay://` URL. The URL scheme is a third automation front door
/// (alongside the CLI and App Intents); like them it routes onto the shared `CommandGateway`, so it
/// inherits the same safety, verification, and audit path.
///
/// Security: a URL can be triggered by any app or web link, so only non-destructive recovery actions
/// are safe to auto-run. Arrangement-altering commands are still *parsed*, but flagged
/// `requiresConfirmation` so the host refuses to apply them silently and instead asks for in-app
/// confirmation.
public enum URLCommand: Hashable, Sendable {
    /// Reconnect every managed-offline display — the always-available recovery action. Safe to auto-run.
    case reconnectAll
    /// Logically disconnect the display named by `selector`. Arrangement-altering → must be confirmed
    /// in-app, never fired silently from a URL.
    case disconnect(selector: String)

    /// True for commands that change the active arrangement or are otherwise destructive. The URL
    /// handler must NOT execute these without explicit in-app confirmation.
    public var requiresConfirmation: Bool {
        switch self {
        case .reconnectAll: return false
        case .disconnect: return true
        }
    }

    /// Stable short name for logs and the audit trail.
    public var name: String {
        switch self {
        case .reconnectAll: return "reconnectAll"
        case .disconnect: return "disconnect"
        }
    }
}

/// Parses `opendisplay://` URLs into `URLCommand`s. Pure and total: any URL that isn't a recognized
/// command returns `nil`, so the caller logs a no-op instead of ever crashing on malformed input.
public enum URLCommandParser {
    public static let scheme = "opendisplay"

    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // The verb is the URL host (opendisplay://reconnect-all); tolerate a path form too.
        let host = components?.host ?? url.host
        let pathVerb = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let verb = ((host?.isEmpty == false ? host : nil) ?? pathVerb).lowercased()
        guard !verb.isEmpty else { return nil }

        let params = Dictionary(
            (components?.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name.lowercased(), value)
            },
            uniquingKeysWith: { _, last in last }
        )

        switch verb {
        case "reconnect-all", "reconnectall", "reconnect_all":
            return .reconnectAll
        case "disconnect":
            guard let selector = params["display"] ?? params["target"],
                  !selector.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return .disconnect(selector: selector)
        default:
            return nil
        }
    }
}
