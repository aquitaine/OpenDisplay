import Foundation

/// A parsed `major.minor.patch` version. Tolerates a leading `v` and a trailing pre-release/build
/// suffix (`0.5.0-beta.1` parses as 0.5.0); anything else non-numeric fails the parse so the caller
/// can decline to compare rather than guess.
public struct SemanticVersion: Hashable, Sendable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var core = string.hasPrefix("v") || string.hasPrefix("V") ? String(string.dropFirst()) : string
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = String(core[..<cut])
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Outcome of comparing the running version against the newest published release.
public enum UpdateAvailability: Hashable, Sendable {
    /// The running build is the latest (or newer — a dev build ahead of the last release).
    case upToDate
    /// A newer release exists; `version` is its display string, `url` its release page.
    case available(version: String, url: String)
}

/// Pure decision logic for the update check — version comparison and auto-check throttling. The
/// network fetch and persistence live app-side; everything here is deterministic and unit-tested.
public enum UpdateCheckPolicy {
    /// Compares the running version with the latest release tag. Returns nil when either side
    /// doesn't parse — an unparseable tag must not produce an "update available" prompt.
    public static func availability(
        current: String, latestTag: String, releaseURL: String
    ) -> UpdateAvailability? {
        guard let current = SemanticVersion(current),
              let latest = SemanticVersion(latestTag) else { return nil }
        guard latest > current else { return .upToDate }
        var display = latestTag
        if display.hasPrefix("v") || display.hasPrefix("V") { display.removeFirst() }
        return .available(version: display, url: releaseURL)
    }

    /// Whether a background (non-user-initiated) check is due. A never-checked install is due
    /// immediately; afterwards at most once per `minimumInterval` (default 24h). A `lastCheck` in
    /// the future (clock rolled back) counts as due rather than silencing checks indefinitely.
    public static func shouldAutoCheck(
        lastCheck: Date?, now: Date, minimumInterval: TimeInterval = 24 * 60 * 60
    ) -> Bool {
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= minimumInterval
    }
}
