import Foundation
import TopologyCore

/// Fetches the newest published release from GitHub and compares it against the running build.
/// Decision logic (version compare, throttling) lives in `UpdateCheckPolicy` (TopologyCore, tested);
/// this file is only the I/O: one anonymous GET to the public releases API, nothing downloaded,
/// nothing sent beyond the request itself.
enum UpdateChecker {
    struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static let releasesPage = "https://github.com/aquitaine/OpenDisplay/releases/latest"
    private static let latestAPI = "https://api.github.com/repos/aquitaine/OpenDisplay/releases/latest"

    /// The running build's marketing version ("0.4.1").
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Asks GitHub for the latest release and returns the comparison result, or nil when the network
    /// or the tag is unusable — callers treat nil as "unknown", never as "update available".
    static func fetchAvailability() async -> UpdateAvailability? {
        guard let url = URL(string: latestAPI) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else {
            return nil
        }
        return UpdateCheckPolicy.availability(
            current: currentVersion, latestTag: release.tagName, releaseURL: release.htmlURL)
    }
}
