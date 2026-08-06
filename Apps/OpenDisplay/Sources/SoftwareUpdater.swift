#if os(macOS)
import AppKit
import Sparkle
import TopologyCore

/// One-click updates, backed by Sparkle 2: check → download → verify (EdDSA signature + Developer ID
/// code signature) → install → relaunch, all inside Sparkle's own windows. This file is the I/O shell
/// only — every decision it makes (how a phase advances, whether a release may be installed, what the
/// updater may do unattended) lives in `SoftwareUpdatePolicy`, which `make test` exercises.
///
/// Two Sparkle behaviours are deliberately overridden for a menu-bar app:
///
///   * **Gentle reminders.** A scheduled check that finds an update must not throw a window in front
///     of whatever the user is doing. Unless Sparkle itself proposes to show it in immediate focus
///     (right after launch, or an idle machine), the find is reported only as the menu's "Update
///     available" badge, and Sparkle's window waits until the user clicks it.
///   * **Activation.** `LSUIElement` apps aren't brought forward automatically, so any window Sparkle
///     is about to show is preceded by activating the app — otherwise the update alert can open
///     behind the frontmost app and look like nothing happened.
///
/// Sparkle holds both delegates weakly, so this object must outlive the updater — `AppModel` owns it
/// for the lifetime of the app.
@MainActor
final class SoftwareUpdater: NSObject {
    /// Called on the main actor whenever `phase` changes. `AppModel` mirrors it into a published
    /// property; nothing in this file knows about SwiftUI.
    var onPhaseChange: ((SoftwareUpdatePhase) -> Void)?

    /// Called when the user changes the automatic-download preference from inside Sparkle's own
    /// update window ("Automatically download and install updates in the future"), so that choice is
    /// written to the app's settings file rather than quietly reverting at the next launch.
    var onAutomaticDownloadPreferenceChange: ((Bool) -> Void)?

    /// What the UI should currently say about updates.
    private(set) var phase: SoftwareUpdatePhase = .idle {
        didSet {
            guard phase != oldValue else { return }
            onPhaseChange?(phase)
        }
    }

    /// Sparkle's updater plus its standard UI. Lazy because both delegates are `self`, which doesn't
    /// exist until `super.init()` has run; `init` touches it immediately, so this is an
    /// initialisation-order detail rather than deferred work.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)

    /// Watches Sparkle's automatic-download flag so its in-window checkbox reaches the settings file.
    private var automaticDownloadObservation: NSKeyValueObservation?

    /// Starts the updater with the user's preferences already applied, so Sparkle's first scheduled
    /// cycle (which begins on the next runloop pass) sees the settings the user actually chose.
    init(behavior: AutomaticUpdateBehavior) {
        super.init()
        apply(behavior)
        observeAutomaticDownloadPreference()
        updaterController.startUpdater()
    }

    /// Pushes the user's two update settings into Sparkle.
    ///
    /// Sparkle persists both flags in the app's user defaults and advises against keeping a second
    /// copy. OpenDisplay keeps one anyway — `settings.json` is the single place every other toggle in
    /// the app lives, and a user who copies that file to a new Mac expects their update preference to
    /// come with it. The duplication is one-way: this app's settings are authoritative and are written
    /// into Sparkle at launch and on every change, so Sparkle's defaults are a mirror rather than a
    /// second source of truth. The single path back is the checkbox in Sparkle's own update window —
    /// see `observeAutomaticDownloadPreference`. Sparkle re-schedules its cycle after either flag
    /// changes, so no explicit reset is needed here.
    func apply(_ behavior: AutomaticUpdateBehavior) {
        updaterController.updater.automaticallyChecksForUpdates = behavior.checksForUpdates
        updaterController.updater.automaticallyDownloadsUpdates = behavior.downloadsAndInstalls
    }

    /// The user asked about updates — from the menu, the About window, or Settings. Sparkle takes it
    /// from here: the progress, the release notes, the download, and the relaunch prompt are all its
    /// windows. Asking again while an update is already on screen simply brings that window forward.
    ///
    /// The guard matters. In the one state where Sparkle won't accept a check — a background download
    /// of its own is mid-flight — it drops the request silently, and a phase moved to `checking` would
    /// sit on a spinner no callback ever clears.
    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else { return }
        NotificationCenter.default.post(name: .openDisplayDismissMenu, object: nil)
        activateForUpdaterWindow()
        record(.checkStarted)
        updaterController.updater.checkForUpdates()
    }

    /// Mirrors Sparkle's automatic-download flag back into the app's settings, which is what makes the
    /// checkbox in Sparkle's update window stick.
    ///
    /// Changes are only mirrored while automatic checks are on. `apply` derives the flag as
    /// "download AND check", so turning automatic checks off writes a `false` here that says nothing
    /// about what the user wants downloaded — mirroring that one back would erase their preference
    /// the moment they paused update checks.
    private func observeAutomaticDownloadPreference() {
        automaticDownloadObservation = updaterController.updater.observe(
            \.automaticallyDownloadsUpdates, options: [.new]
        ) { [weak self] _, change in
            guard let downloadsAutomatically = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.updaterController.updater.automaticallyChecksForUpdates else { return }
                self.onAutomaticDownloadPreferenceChange?(downloadsAutomatically)
            }
        }
    }

    /// The running build's marketing version ("0.9.0"), the left-hand side of the downgrade guard.
    private var runningVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func record(_ event: SoftwareUpdateEvent) {
        phase = SoftwareUpdatePolicy.phase(after: event, from: phase)
    }

    /// Brings the app forward so a window Sparkle is about to show lands in front. A menu-bar
    /// (`LSUIElement`) app has no Dock icon to bounce and isn't activated for it automatically.
    private func activateForUpdaterWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Why the downgrade guard turned an update away. Sparkle surfaces `errorDescription` verbatim, so it
/// is written for the person reading the alert rather than for a log.
private struct DowngradeRefused: LocalizedError {
    let advertised: String
    let running: String

    var errorDescription: String? {
        "The update feed offers OpenDisplay \(advertised), which is older than the \(running) you are "
            + "running. Nothing was installed."
    }
}

// MARK: - Updater delegate (what Sparkle found, and what it may do)

extension SoftwareUpdater: SPUUpdaterDelegate {
    /// The app owns this preference in its own Settings, so Sparkle's second-launch permission prompt
    /// would be a duplicate question with a different answer store.
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    /// The downgrade guard. Sparkle selects its update by build number, so a feed that lists releases
    /// out of order can offer a genuinely older app; `SoftwareUpdatePolicy` refuses that and defers to
    /// Sparkle whenever the two versions can't be compared.
    func updater(
        _ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        let advertised = updateItem.displayVersionString
        guard SoftwareUpdatePolicy.mayInstall(advertised: advertised, running: runningVersion) else {
            throw DowngradeRefused(advertised: advertised, running: runningVersion)
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        record(.updateFound(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        record(.noUpdateFound)
    }

    /// "Skip This Version" means don't remind me — so the badge goes away with it. A plain dismissal
    /// ("Remind Me Later") deliberately leaves the badge up.
    func updater(
        _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard choice == .skip else { return }
        record(.updateSkipped)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        record(.installationStarted)
    }

    /// Fires at the end of every cycle, with or without an error — the one hook that reliably clears a
    /// check which produced no verdict (offline, rate-limited, cancelled).
    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?
    ) {
        record(.checkFinished)
    }
}

// MARK: - Standard user driver delegate (when Sparkle's own windows appear)

/// Sparkle calls this protocol from its standard user driver, which is itself main-actor-bound, so
/// every callback arrives on the main thread; the `assumeIsolated` hops below are assertions of that
/// fact rather than thread hops. The protocol isn't annotated for Swift concurrency, which is why the
/// conformances have to be declared `nonisolated`.
extension SoftwareUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show a scheduled update only when it already proposes to do so in immediate focus
    /// (just after launch, or an idle machine). Otherwise the menu badge is the whole reminder, and
    /// the window waits for the user to click it.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated { activateForUpdaterWindow() }
    }

    /// A modal alert would otherwise open behind the menu-bar pop-out, which sits above ordinary
    /// windows; closing the pop-out first also matches what every other window-opening action does.
    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated {
            NotificationCenter.default.post(name: .openDisplayDismissMenu, object: nil)
            activateForUpdaterWindow()
        }
    }
}
#endif
