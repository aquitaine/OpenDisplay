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

/// How a release advertised in the update feed stands relative to the running build.
public enum ReleaseRelation: Hashable, Sendable {
    /// Newer than what's running; `version` is its display string (a leading `v` stripped).
    case newer(version: String)
    /// The same marketing version — typically a re-built release of what is already installed.
    case same
    /// Behind the running build: a dev build ahead of the feed, or a mis-ordered release.
    case older
}

/// Where the app is in an update session, as far as its own UI is concerned. The updater (Sparkle)
/// owns the download, the signature check, the install, and every window shown along the way; this is
/// only what the menu row and the About window need in order to render one honest line.
public enum SoftwareUpdatePhase: Hashable, Sendable {
    /// Nothing known: the launch state, and where a check that produced no verdict lands.
    case idle
    /// A check is in flight — the user's, or the updater's scheduled one.
    case checking
    /// The last check found nothing newer.
    case upToDate
    /// A newer release is waiting; `version` is its display string ("0.9.1").
    case available(version: String)
    /// The update is being installed and the app is about to relaunch.
    case installing
}

/// What the updater just reported — one case per thing the app can observe, so the phase machine
/// below stays a pure function of (phase, event) and is exercised by `make test`.
public enum SoftwareUpdateEvent: Hashable, Sendable {
    /// A check began.
    case checkStarted
    /// A newer release was found; `version` is its display string.
    case updateFound(version: String)
    /// The feed had nothing newer to offer.
    case noUpdateFound
    /// The user chose "Skip This Version" — they aren't reminded again unless they ask.
    case updateSkipped
    /// Installation started; the relaunch follows.
    case installationStarted
    /// The update cycle ended, with or without an error.
    case checkFinished
}

/// How one update affordance — the menu row, the About window's button — should render. Both surfaces
/// read the same value, so they can't drift apart on wording, icon, or when the control is live.
public struct SoftwareUpdatePresentation: Hashable, Sendable {
    /// The row's label ("Check for Updates…").
    public let title: String
    /// SF Symbol shown beside the title.
    public let systemImage: String
    /// Trailing version pill, when there is a version worth showing.
    public let badge: String?
    /// True while work is in flight: the surface shows a spinner and the control isn't clickable.
    public let showsProgress: Bool

    public init(title: String, systemImage: String, badge: String? = nil, showsProgress: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
        self.showsProgress = showsProgress
    }

    /// Title with the badge folded in ("Update available: 0.9.1"), for the surfaces that render the
    /// whole state on one line rather than as a row plus a pill.
    public var combinedTitle: String {
        guard let badge else { return title }
        return "\(title): \(badge)"
    }
}

/// What the updater may do unattended, derived from the two user settings.
public struct AutomaticUpdateBehavior: Hashable, Sendable {
    /// Check the feed on a schedule.
    public let checksForUpdates: Bool
    /// Download a found update and install it without being asked each time.
    public let downloadsAndInstalls: Bool

    public init(checksForUpdates: Bool, downloadsAndInstalls: Bool) {
        self.checksForUpdates = checksForUpdates
        self.downloadsAndInstalls = downloadsAndInstalls
    }
}

/// Pure decision logic for software updates: how a release compares to the running build, how the UI
/// phase advances as the updater reports events, how each phase renders, and what the updater may do
/// unattended. Deterministic and unit-tested; the Sparkle plumbing that feeds it is app-side in
/// `SoftwareUpdater`, which stays a thin I/O shell.
public enum SoftwareUpdatePolicy {
    /// Compares an advertised release against the running build. Returns nil when either side doesn't
    /// parse — an unparseable version must not produce a verdict a caller can act on.
    public static func relation(
        ofAdvertised advertised: String, toRunning running: String
    ) -> ReleaseRelation? {
        guard let runningVersion = SemanticVersion(running),
              let advertisedVersion = SemanticVersion(advertised) else { return nil }
        guard advertisedVersion > runningVersion else {
            return advertisedVersion == runningVersion ? .same : .older
        }
        var display = advertised
        if display.hasPrefix("v") || display.hasPrefix("V") { display.removeFirst() }
        return .newer(version: display)
    }

    /// Whether a release the feed offers may be installed over the running build. Sparkle picks its
    /// update by build number (`CFBundleVersion`), so a feed listing releases out of order — a hotfix
    /// for an older line published after a newer one — can offer a real downgrade. Refusing that is
    /// the same belt-and-braces posture the display transactions take; when the two versions can't be
    /// compared at all we defer to the updater rather than block a legitimate update.
    public static func mayInstall(advertised: String, running: String) -> Bool {
        relation(ofAdvertised: advertised, toRunning: running) != .older
    }

    /// The phase an `event` moves the UI to. Three rules carry the interesting behaviour: a cycle that
    /// ends without a verdict (offline, rate-limited, cancelled) falls back to `idle` rather than
    /// claiming the app is up to date; an ending cycle never retracts a phase that already has
    /// something to say — dismissing the update alert leaves the "Update available" badge standing,
    /// which is the entire point of a gentle reminder; and a phase that already found something is
    /// sticky across a new check, because clicking a badged row only brings the updater's own window
    /// back into focus and swapping the badge for a spinner would strand the row if no fresh cycle
    /// runs at all.
    public static func phase(
        after event: SoftwareUpdateEvent, from phase: SoftwareUpdatePhase
    ) -> SoftwareUpdatePhase {
        switch event {
        case .checkStarted:
            switch phase {
            case .available, .installing: return phase
            case .idle, .checking, .upToDate: return .checking
            }
        case .updateFound(let version):
            return .available(version: version)
        case .noUpdateFound:
            return .upToDate
        case .updateSkipped:
            return .idle
        case .installationStarted:
            return .installing
        case .checkFinished:
            return phase == .checking ? .idle : phase
        }
    }

    /// How `phase` renders on a menu row or in the About window.
    public static func presentation(for phase: SoftwareUpdatePhase) -> SoftwareUpdatePresentation {
        switch phase {
        case .idle:
            return SoftwareUpdatePresentation(title: "Check for Updates…", systemImage: "arrow.down.circle")
        case .checking:
            return SoftwareUpdatePresentation(
                title: "Checking for updates…", systemImage: "arrow.down.circle", showsProgress: true)
        case .upToDate:
            return SoftwareUpdatePresentation(title: "Up to date", systemImage: "checkmark.circle")
        case .available(let version):
            return SoftwareUpdatePresentation(
                title: "Update available", systemImage: "arrow.down.circle.fill", badge: version)
        case .installing:
            return SoftwareUpdatePresentation(
                title: "Installing update…", systemImage: "arrow.down.circle.fill", showsProgress: true)
        }
    }

    /// What the updater may do unattended, given the two settings. Downloading is gated on checking:
    /// an updater that never looks at the feed can't install from it, so the download preference is
    /// remembered but inert until automatic checks are on — the same way Sparkle reads the pair (see
    /// its `allowsAutomaticUpdates`).
    public static func automaticBehavior(
        checkEnabled: Bool, downloadEnabled: Bool
    ) -> AutomaticUpdateBehavior {
        AutomaticUpdateBehavior(
            checksForUpdates: checkEnabled, downloadsAndInstalls: checkEnabled && downloadEnabled)
    }
}
