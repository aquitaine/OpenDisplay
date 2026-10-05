import Foundation

/// Scrubs OpenDisplay's own settings before they go into a diagnostics bundle.
///
/// A bundle is something a user attaches to a public GitHub issue, so it carries what explains a
/// display problem and nothing that describes the person: no location (Location Mode's
/// coordinates), and no list of which apps they have presets for. Everything else in the settings
/// file is display configuration, which is the point of the bundle. ::
///
///     {"adaptiveLatitude": 51.5, "appPresets": [{…}, {…}], "osdEnabled": true}
///     ok: {"adaptiveLatitude": "<redacted>", "appPresets": "<2 redacted>", "osdEnabled": true}
public enum DiagnosticsRedaction {
    static let locationMarkers = ["latitude", "longitude", "coordinate", "location"]
    static let listKeys: Set<String> = ["appPresets", "appPresetPriorStateByDisplay"]

    /// Redacted settings JSON, or nil when `data` isn't a JSON object (then nothing is included).
    public static func redactedSettings(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: redact(object),
                                           options: [.prettyPrinted, .sortedKeys])
    }

    static func redact(_ value: Any, key: String? = nil) -> Any {
        if let key {
            if listKeys.contains(key) { return "<\(count(of: value)) redacted>" }
            let lowered = key.lowercased()
            // A flag such as `adaptiveLocationModeEnabled` says nothing about where anyone is.
            if !(value is Bool), locationMarkers.contains(where: lowered.contains) { return "<redacted>" }
        }
        if let dictionary = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key, redact($0.value, key: $0.key)) })
        }
        if let array = value as? [Any] { return array.map { redact($0) } }
        return value
    }

    private static func count(of value: Any) -> Int {
        (value as? [Any])?.count ?? (value as? [String: Any])?.count ?? 0
    }
}
