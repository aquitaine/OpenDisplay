#if os(macOS)
import AppKit
import AutomationSchema
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import ProviderInterfaces
import SceneEngine
import TopologyCore
#if !PUBLIC_API_ONLY
import ExperimentalLifecycleProvider
#endif

/// A hardware (DDC) control the menu can offer for an external display. Public-safe (no private-SPI
/// types), so the menu can reference it in every build; AppModel maps it to a DDC VCP code.
enum HardwareControl: CaseIterable, Hashable {
    case contrast, volume, sharpness, redGain, greenGain, blueGain

    var vcp: UInt8 {
        switch self {
        case .contrast: return 0x12
        case .volume: return 0x62
        case .sharpness: return 0x87
        case .redGain: return 0x16
        case .greenGain: return 0x18
        case .blueGain: return 0x1A
        }
    }
    var label: String {
        switch self {
        case .contrast: return "Contrast"
        case .volume: return "Volume"
        case .sharpness: return "Sharpness"
        case .redGain: return "Red gain"
        case .greenGain: return "Green gain"
        case .blueGain: return "Blue gain"
        }
    }
    var icon: String {
        switch self {
        case .contrast: return "circle.lefthalf.filled"
        case .volume: return "speaker.wave.2"
        case .sharpness: return "triangle.lefthalf.filled"
        case .redGain: return "r.circle"
        case .greenGain: return "g.circle"
        case .blueGain: return "b.circle"
        }
    }
}

/// Which route a display's unified brightness slider drives. Resolved per display when brightness is
/// read: built-in panels use the OS (`native`), externals that answer DDC use `hardware`, and anything
/// else falls back to `software` gamma dimming (works on any display). Surfaced as a small caption so
/// the single slider stays honest about *how* it's dimming.
enum BrightnessMethod: String, Hashable {
    case native, hardware, software

    /// Caption shown beneath the slider. `native` needs none — it *is* the system brightness.
    var caption: String? {
        switch self {
        case .native: return nil
        case .hardware: return "Hardware · DDC"
        case .software: return "Software · gamma"
        }
    }
}

/// Build/runtime feature flags for the experimental control paths (PRD: risky behaviour is opt-in).
enum FeatureFlags {
    /// ICC profile writing uses *public* ColorSync, so it's App-Store-safe and on by default.
    static var iccProfileWrite: Bool { true }
    #if !PUBLIC_API_ONLY
    /// Rotation writing uses a *private* API — OFF unless explicitly enabled, and the whole path is
    /// compiled out of the public-API-only / App Store build.
    static var experimentalRotation: Bool { UserDefaults.standard.bool(forKey: "OpenDisplayExperimentalRotation") }
    #else
    static var experimentalRotation: Bool { false }
    #endif
}

/// The app's composition root. It wires the platform-independent `TopologyCoordinator`
/// (Packages/TopologyCore) to a display system and exposes an observable snapshot for the UI.
///
/// M0: observation comes from the real `CoreGraphicsProvider` (live enumeration + a
/// reconfiguration event source). The lifecycle path prefers the experimental SkyLight provider
/// (true logical disconnect, full build only) and falls back to `CoreGraphicsProvider`'s public,
/// reversible mirroring approach — selected by `RoutedLifecycleProvider`. In the public-API-only
/// build the experimental module is absent and the public provider is used directly.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [DisplayObservation] = []
    @Published private(set) var statusText = "Scanning…"
    @Published private(set) var busy = false
    @Published private(set) var diagnostics: [DisplayDiagnostic] = []
    @Published private(set) var phase: DisplayLoadPhase = .scanning
    @Published private(set) var recentActivity: [AuditEntry] = []
    /// Identity records for the current displays, keyed by the observation's record id.
    @Published private(set) var records: [DisplayRecordID: DisplayRecord] = [:]
    @Published private(set) var scenes: [Scene] = []
    /// Non-fatal note from the last scene apply (e.g. rotation skipped) — shown in the Scenes tab.
    @Published var sceneWarning: String?
    /// Displays the app has logically turned off. The OS drops them from the online list, so we track
    /// them here to keep an "off" card in the menu (with a way back on) and to feed the safety net.
    @Published private(set) var managedOffline: [OfflineDisplay] = []
    /// Cached brightness (0...1) for displays we can control — built-in via DisplayServices, externals
    /// via DDC, or software gamma as a universal fallback. A missing key means "not yet read".
    @Published private(set) var brightness: [DisplayRecordID: Float] = [:]
    /// The route the unified brightness slider drives for each display (resolved on read).
    @Published private(set) var brightnessMethod: [DisplayRecordID: BrightnessMethod] = [:]
    /// The display selected in the Settings → Displays detail pane. The menu bar sets this when it
    /// deep-links into Settings ("Display settings…"), so the right display is shown on arrival.
    @Published var selectedDisplayID: DisplayRecordID?
    /// Opt-in toggle for the experimental (private-API) rotation writer; persisted to UserDefaults.
    /// Drives the rotation backend live and stays false in the public-API-only build.
    @Published var experimentalRotationEnabled: Bool = FeatureFlags.experimentalRotation {
        didSet { UserDefaults.standard.set(experimentalRotationEnabled, forKey: "OpenDisplayExperimentalRotation") }
    }
    /// Cached DDC hardware-control levels (0...1) keyed by display then VCP code (contrast/volume).
    @Published private(set) var ddcControlLevel: [DisplayRecordID: [UInt8: Float]] = [:]
    /// Cached DDC capabilities (VCP 0xF3) per external display (Batch-2 #1): what the panel advertises,
    /// so the UI/CLI only offer supported controls. Absent = not yet read → fall back to offering all.
    @Published private(set) var ddcCapabilities: [DisplayRecordID: DDCCapabilities] = [:]
    /// Per-display software (gamma) dim level, 1 = no dim. Applies on top of hardware brightness and
    /// works on any display, including DDC-less externals and below the hardware minimum.
    @Published private(set) var softwareDim: [DisplayRecordID: Float] = [:]
    /// Current DDC input-source code (VCP 0x60) per external display.
    @Published private(set) var inputSource: [DisplayRecordID: Int] = [:]
    /// Current DDC colour-preset code (VCP 0x14) per external display, and the max code it reports.
    @Published private(set) var colorPreset: [DisplayRecordID: Int] = [:]
    @Published private(set) var colorPresetMax: [DisplayRecordID: Int] = [:]
    /// Current ICC colour-profile name per display (ColorSync), for the Colour profile row.
    @Published private(set) var colorProfileName: [DisplayRecordID: String] = [:]
    /// Whether each display exposes a ColorSync device that profile writes can target — resolved
    /// off-main and cached so the menu never probes ColorSync during a view body.
    @Published private(set) var colorProfileControllable: [DisplayRecordID: Bool] = [:]
    /// Installed ICC profiles the user can assign, enumerated off-main once and cached (the scan reads
    /// and parses every installed profile from disk, so it must never run during a SwiftUI body).
    @Published private(set) var availableColorProfilesCache: [ICCProfile] = []

    /// Standard DDC colour-preset labels (VCP 0x14). Monitors vary; the menu offers 1...max and labels
    /// the standard ones, falling back to "Preset N".
    static let presetNames: [Int: String] = [
        1: "sRGB", 2: "Display native", 3: "4000K", 4: "5000K", 5: "6500K",
        6: "7500K", 7: "8200K", 8: "9300K", 9: "10000K", 11: "User 1",
    ]
    func presetName(_ code: Int) -> String { Self.presetNames[code] ?? "Preset \(code)" }

    /// Common DDC/CI input-source codes (VCP 0x60). Monitors mostly follow these; the menu shows the
    /// live code too, so a non-standard panel is still legible.
    static let standardInputs: [(name: String, code: Int)] = [
        ("HDMI 1", 0x11), ("HDMI 2", 0x12), ("DisplayPort 1", 0x0F), ("DisplayPort 2", 0x10),
        ("USB-C", 0x1B), ("DVI", 0x03), ("VGA", 0x01),
    ]

    /// Human label for a DDC input code, or "Code N" if non-standard.
    func inputName(_ code: Int) -> String {
        Self.standardInputs.first { $0.code == code }?.name ?? "Code \(code)"
    }

    /// A display OpenDisplay turned off — remembered (and persisted) so it stays visible and
    /// re-enableable even across app restarts, and so the watchdog can always recover it.
    struct OfflineDisplay: Identifiable, Equatable, Codable {
        let recordID: DisplayRecordID
        let cgID: CGDirectDisplayID
        let name: String
        let displayClass: DisplayClass
        var id: DisplayRecordID { recordID }
    }

    /// Count of currently-active displays — the UI disables the off-toggle on the last one.
    var activeDisplayCount: Int { displays.filter(\.isActive).count }

    /// True when any provider isn't fully supported — drives the menu-bar caution banner.
    var isDegraded: Bool { diagnostics.contains { $0.status != "supported" } }

    private let observer: CoreGraphicsProvider
    private let coordinator: TopologyCoordinator
    private let checkpoints: any CheckpointStoring
    private let lifecycle: any LifecycleProvider
    /// Read-only by default; the experimental SkyLight rotator is selected only when the opt-in toggle
    /// is on (and is compiled out of the public-API-only build entirely). Computed so toggling the
    /// setting takes effect immediately, without a relaunch.
    private var rotationBackend: any RotationBackend {
        #if !PUBLIC_API_ONLY
        if experimentalRotationEnabled { return ExperimentalRotationBackend() }
        #endif
        return ReadOnlyRotationBackend()
    }
    #if !PUBLIC_API_ONLY
    private let brightnessControl = DisplayServicesBrightnessProvider()
    private var ddc: [DisplayRecordID: ExternalDisplayDDC] = [:]
    /// In-flight DDC-controller constructions, so concurrent first-uses of one display await the same
    /// build instead of each spinning up (and binding) a duplicate IOAVService.
    private var ddcBuilders: [DisplayRecordID: Task<ExternalDisplayDDC?, Never>] = [:]
    private var brightnessMax: [DisplayRecordID: Int] = [:]
    private var ddcTarget: [DisplayRecordID: Int] = [:]
    private var ddcWriters: [DisplayRecordID: Task<Void, Never>] = [:]
    private struct DDCControlKey: Hashable { let id: DisplayRecordID; let vcp: UInt8 }
    private var ddcControlMax: [DDCControlKey: Int] = [:]
    private var ddcControlTarget: [DDCControlKey: Int] = [:]
    private var ddcControlWriter: [DDCControlKey: Task<Void, Never>] = [:]
    private var inputSourceTarget: [DisplayRecordID: Int] = [:]
    private var inputSourceWriter: [DisplayRecordID: Task<Void, Never>] = [:]
    private var colorPresetTarget: [DisplayRecordID: Int] = [:]
    private var colorPresetWriter: [DisplayRecordID: Task<Void, Never>] = [:]
    /// Per-display negative cache of VCP features that repeatedly failed to read, so refresh passes
    /// stop spending ~0.7s of retried I2C on every control the panel doesn't implement (with a
    /// periodic recheck baked into the tracker — see `DDCProbeTracker`). Dropped on disconnect.
    private var ddcProbe: [DisplayRecordID: DDCProbeTracker] = [:]
    /// Adaptive Display (Labs): per-display policy state. Published so the detail card's status
    /// line updates as the loop acts. All decisions live in the pure `AdaptiveDisplayPolicy`.
    @Published private(set) var adaptiveStates: [DisplayRecordID: AdaptiveDisplayPolicy.DisplayState] = [:]
    private var adaptiveLoop: Task<Void, Never>?
    private let nightShift = NightShiftStatusReader()
    private let ambientLight = AmbientLightReader()
    /// EMA-smoothed ambient lux (α=0.4 toward the newest sample) so a hand shadow over the sensor
    /// doesn't ripple into DDC writes; nil when the sensor is unreadable (lid closed).
    private var ambientLuxEMA: Double?
    #endif
    private var hotKeys: [GlobalHotKey] = []
    private var registry: DisplayRegistry?
    private var sceneLibrary: SceneLibrary?
    /// Persisted user settings. Mutated only through the dedicated setters (which also persist and
    /// reconcile side effects), so the on-disk store and any derived state stay in lockstep.
    @Published private(set) var settings: OpenDisplaySettings
    /// On-disk settings store (Application Support); nil only if that directory can't be resolved.
    private let settingsStore: SettingsStore?
    /// Holds the "prevent display idle-sleep" power assertion while the toggle is on and an external
    /// display is present (Issue 3). Decision logic is the platform-independent `DisplaySleepGuard`.
    private let sleepGuard: DisplaySleepGuard

    /// Pinned favourite resolutions per display (Batch-2 #3), persisted to favorites.json.
    @Published private(set) var favorites = FavoriteResolutions()
    private let favoritesStore: FavoritesStore?

    /// Live "Keep these settings?" prompt for an arrangement-altering change (Issue 6), or nil when no
    /// revert window is open. Drives the countdown banner; the UI calls `confirmArrangementChange()` /
    /// `revertArrangementChange()`.
    @Published private(set) var pendingRevert: PendingRevert?
    /// UI state for the timed auto-revert banner.
    struct PendingRevert: Equatable { var message: String; var secondsRemaining: Int }
    /// Decision core for the open revert window; `before` is the arrangement to restore on timeout.
    private var revertGate: TimedRevertGate<[DisplayObservation]>?
    private var revertMessage = ""
    private var revertTask: Task<Void, Never>?

    /// Edge detector for "auto-disconnect the built-in when an external connects" (Issue 5). Seeded to
    /// the launch topology so a pre-attached external isn't treated as a fresh arrival.
    private var autoDisconnectPolicy = AutoDisconnectBuiltInPolicy()

    /// Native-looking OSD HUD for brightness/volume changes (Batch-3 #4).
    private let osdHUD = OSDHUDController()
    /// Active media-key event tap (Batch-3 #3) when interception is on AND Accessibility is granted.
    private var mediaKeyTap: MediaKeyTap?
    /// Re-arms the media-key tap once the Accessibility grant lands. TCC has no notification API, so
    /// without this poll the user must relaunch the app after granting — the #1 "keys don't work" trap.
    private var mediaKeyTapRetry: Task<Void, Never>?
    /// One system Accessibility prompt per launch, max — reconcile runs on every toggle change and at
    /// init, and re-prompting each time would nag.
    private var promptedForAccessibility = false
    /// Remembered pre-mute DDC volume per display, so a mute toggle can restore the prior level.
    private var preMuteVolume: [DisplayRecordID: Float] = [:]

    init() {
        let observer = CoreGraphicsProvider()
        self.observer = observer
        let checkpoints = AppModel.makeCheckpointStore()
        self.checkpoints = checkpoints
        let lifecycle = AppModel.makeLifecycleProvider(public: observer)
        self.lifecycle = lifecycle
        self.coordinator = TopologyCoordinator(
            observer: observer,
            lifecycleProvider: lifecycle,
            checkpoints: checkpoints,
            // A disconnect from the menu/CLI is an explicit user action, so confirm the SafetyEngine's
            // `.needsConfirmation` cases (e.g. turning off the current main). The engine's hard
            // `.blocked` cases — chiefly "this would leave no active display" — are NOT bypassable here.
            confirm: { _, _ in true }
        )
        let settingsStore = (try? SettingsStore.defaultDirectory()).map(SettingsStore.init(directory:))
        self.settingsStore = settingsStore
        self.settings = settingsStore?.load() ?? .default
        self.sleepGuard = DisplaySleepGuard(backend: IOKitPowerAssertions())
        let favoritesStore = (try? SettingsStore.defaultDirectory()).map(FavoritesStore.init(directory:))
        self.favoritesStore = favoritesStore
        self.favorites = favoritesStore?.load() ?? FavoriteResolutions()
        // Register the configurable global hotkeys (Batch-2 #4). Reconnect-All is always-available
        // (recovery hierarchy step 3) and reachable even when the menu bar isn't; the rest are unbound
        // by default. A chord that can't be claimed is simply skipped (menu-bar item remains).
        registerHotkeys()
        reconcileMediaKeyTap()  // Batch-3 #3: arm the media-key tap if enabled + Accessibility granted
        if settings.displayNotificationsEnabled { NotificationDelivery.requestAuthorization() }  // Batch-2 #5
        #if DEBUG
        FileHandle.standardError.write(Data("Global hotkeys registered: \(hotKeys.count)\n".utf8))
        #endif
        Task {
            await setUpRegistry()
            await setUpScenes()
            await loadManagedOffline()
            await refresh()
            await enforceActiveSurfaceInvariant()  // recover if we launched into a stranded (0-active) state
            reconcileDisplaySleepGuard()  // hold/release the keep-awake assertion for the launch topology
            #if !PUBLIC_API_ONLY
            reconcileAdaptiveLoop()  // start adaptive brightness/warmth if enabled for this topology
            #endif
            autoDisconnectPolicy.seed(externalPresent: hasExternalDisplay)  // don't treat a pre-attached external as an arrival
            await writeBaselineCheckpoint()
            if let marker = Self.readRotationMarker() {
                // A prior experimental rotation didn't confirm — restore that display's safe angle and
                // a safe layout, then clear the marker.
                try? await rotationBackend.setRotation(marker.safeAngle, for: marker.cgID)
                _ = await coordinator.reconnectAll()
                Self.clearRotationMarker()
                await refresh()
            }
            if let priorArrangement = Self.readRevertMarker() {
                // An arrangement-revert window was open when the app last died — restore the prior
                // mode/origin/mirror/main so a bad resolution or mirror can't survive a crash/quit.
                await restoreArrangement(priorArrangement)
                Self.clearRevertMarker()
            }
            #if DEBUG
            if let token = ProcessInfo.processInfo.environment["OPENDISPLAY_DISCONNECT"] {
                await debugDisconnectCycle(token: token)
            }
            #endif
        }
        Task { await observeTopologyChanges() }
        // A software gamma dim persists until logout; restore on quit so it never outlives the app.
        // The keep-awake assertion is process-bound, but release it explicitly so it's gone the instant
        // we quit rather than at process teardown.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            CoreGraphicsProvider.restoreGamma()
            MainActor.assumeIsolated {
                self?.sleepGuard.releaseAll()
                self?.mediaKeyTapRetry?.cancel()
                self?.mediaKeyTap?.stop()
                #if !PUBLIC_API_ONLY
                self?.adaptiveLoop?.cancel()
                #endif
            }
        }
    }

    /// Builds the lifecycle provider: experimental-primary + public-fallback in the full build,
    /// the public provider alone in the public-API-only build.
    private static func makeLifecycleProvider(public publicProvider: CoreGraphicsProvider) -> any LifecycleProvider {
        #if PUBLIC_API_ONLY
        return publicProvider
        #else
        return RoutedLifecycleProvider(primary: ExperimentalLifecycleProvider(), fallback: publicProvider)
        #endif
    }

    /// Persistent, rescue-readable checkpoints in Application Support, falling back to in-memory
    /// only if that directory can't be resolved.
    private static func makeCheckpointStore() -> any CheckpointStoring {
        if let directory = try? DiskCheckpointStore.defaultDirectory() {
            return DiskCheckpointStore(directory: directory)
        }
        return InMemoryCheckpointStore()
    }

    /// Records the current arrangement as a last-known-safe baseline so the rescue utility has
    /// something to restore even before any disconnect runs (PRD §9.4).
    private func writeBaselineCheckpoint() async {
        let snapshot = await observer.currentSnapshot()
        let checkpoint = Checkpoint(
            transactionID: TransactionID(rawValue: "txn_baseline"),
            generation: snapshot.generation,
            observations: snapshot.observations,
            mainDisplayID: snapshot.observations.first(where: { $0.isMain })?.recordID,
            managedOffline: snapshot.managedOffline
        )
        try? await checkpoints.writeAtomic(checkpoint)
    }

    /// A human-readable name for a display: the OS-provided localized name when the display is live
    /// (e.g. "Built-in Retina Display", "S34J55x"), otherwise a class + resolution fallback, and
    /// finally the stable record ID. Identity-resolved aliases land later (PRD D-009).
    func displayName(for observation: DisplayObservation) -> String {
        if let alias = records[observation.recordID]?.alias, !alias.isEmpty {
            return alias
        }
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let cgID = observation.cgDisplayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == cgID
           }) {
            return screen.localizedName
        }
        if observation.displayClass == .builtIn { return "Built-in Display" }
        if let mode = observation.mode {
            return "\(observation.displayClass.rawValue.capitalized) · \(mode.pixelWidth)×\(mode.pixelHeight)"
        }
        return observation.recordID.rawValue
    }

    /// Where the rescue-readable checkpoints live, shown in Settings → Diagnostics & Recovery.
    var checkpointLocation: String {
        (try? DiskCheckpointStore.defaultDirectory().path) ?? "(unavailable)"
    }

    /// The bound global recovery hotkey, shown in Settings.
    let reconnectAllHotkey = "⌃⌥⌘R"

    /// Probes the observation + lifecycle providers and publishes their status for Settings.
    func refreshDiagnostics() async {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let environment = ProviderEnvironment(
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            isAppleSilicon: appleSilicon, transport: .unknown, displayClass: .unknown
        )
        let observation = await observer.probe(environment)
        let lifecycleProbe = await lifecycle.probe(environment)
        // Probes are static for a given environment, so republish only when something actually changed
        // (this is read on every topology event to drive the menu-bar "degraded" banner via isDegraded).
        let updated = [
            DisplayDiagnostic(provider: "Core Graphics (observation)", status: observation.status.rawValue,
                              risk: observation.risk.rawValue, experimental: observer.isExperimental,
                              reasons: observation.reasons.map(\.rawValue)),
            DisplayDiagnostic(provider: "Lifecycle (disconnect / reconnect)", status: lifecycleProbe.status.rawValue,
                              risk: lifecycleProbe.risk.rawValue, experimental: lifecycle.isExperimental,
                              reasons: lifecycleProbe.reasons.map(\.rawValue))
        ]
        if diagnostics != updated { diagnostics = updated }
    }

    /// Loads the most recent audit-log entries for Settings → Recent Activity.
    func refreshActivity() async {
        guard let directory = try? DiskAuditLog.defaultDirectory() else { return }
        recentActivity = await DiskAuditLog(directory: directory).recent(limit: 8).reversed()
    }

    private func setUpRegistry() async {
        let store: any RegistryStoring =
            (try? DiskRegistryStore.defaultDirectory()).map { DiskRegistryStore(directory: $0) }
            ?? InMemoryRegistryStore()
        registry = await DisplayRegistry(store: store)
    }

    /// Resolves each live display's fingerprint into the registry (recognizing or minting), so the
    /// menu bar and Settings can show user aliases and remember them across reconnects.
    private func resolveRecords(_ snapshot: TopologySnapshot) async {
        guard let registry else { return }
        let observer = self.observer
        let observations = snapshot.observations.filter { $0.cgDisplayID != nil }
        guard !observations.isEmpty else { if !records.isEmpty { records = [:] }; return }
        // EDID fingerprint reads are nonisolated CG/IOKit accessors — gather them OFF the main actor,
        // then resolve the whole set in ONE batched (single disk-write) registry call.
        let prepared: [(DisplayRecordID, DisplayFingerprint, String?, DisplayClass)] =
            await Task.detached(priority: .utility) {
                observations.compactMap { obs -> (DisplayRecordID, DisplayFingerprint, String?, DisplayClass)? in
                    guard let cgID = obs.cgDisplayID else { return nil }
                    return (obs.recordID, observer.fingerprint(for: cgID), obs.cgUUID, obs.displayClass)
                }
            }.value
        let resolved = await registry.resolveAll(
            prepared.map { (fingerprint: $0.1, cgUUID: $0.2, displayClass: $0.3) }
        )
        var byID: [DisplayRecordID: DisplayRecord] = [:]
        for (input, record) in zip(prepared, resolved) { byID[input.0] = record }
        records = byID
    }

    private func setUpScenes() async {
        let store: any SceneStoring =
            (try? DiskSceneStore.defaultDirectory()).map { DiskSceneStore(directory: $0) }
            ?? InMemorySceneStore()
        let library = await SceneLibrary(store: store)
        sceneLibrary = library
        scenes = await library.all()
    }

    private static func managedOfflineURL() -> URL? {
        (try? DiskCheckpointStore.defaultDirectory())?.appendingPathComponent("managed-offline.json")
    }

    /// Persists the managed-offline list so a turned-off display survives an app restart as a
    /// recoverable off-card (the in-memory-only list was lost on restart, stranding the display).
    private func persistManagedOffline() {
        guard let url = Self.managedOfflineURL() else { return }
        try? JSONEncoder().encode(managedOffline).write(to: url, options: .atomic)
    }

    /// Loads persisted off-displays and reconciles them against the live topology: any that are back
    /// online + active are dropped (they returned on their own); the rest remain as off-cards.
    private func loadManagedOffline() async {
        guard let url = Self.managedOfflineURL(), let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([OfflineDisplay].self, from: data) else { return }
        let snapshot = await observer.currentSnapshot()
        let activeIDs = Set(snapshot.activeDisplays.map(\.recordID))
        managedOffline = saved.filter { !activeIDs.contains($0.recordID) }
        if managedOffline != saved { persistManagedOffline() }
    }

    /// Captures the current arrangement as a named scene (upsert by name).
    func saveScene(named name: String) async {
        guard let sceneLibrary else { return }
        let snapshot = await observer.currentSnapshot()
        let id = await sceneLibrary.scene(named: name)?.id ?? "scene_\(UUID().uuidString.prefix(8))"
        let scene = SceneRecorder.capture(from: snapshot, name: name, id: String(id))
        await sceneLibrary.save(scene)
        scenes = await sceneLibrary.all()
    }

    /// Moves a single display to a new origin (used by the drag-to-arrange canvas), then re-reads
    /// the resulting topology (Core Graphics may adjust neighbours to keep the layout adjacent).
    func setPosition(_ origin: DisplayOrigin, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        _ = observer.applyArrangement([.init(displayID: cgID, origin: origin, mode: nil)])
        await refresh()
    }

    /// Mirrors a display onto the main display (both show the same content) or stops mirroring.
    /// Reversible (public Core Graphics mirroring).
    func setMirrored(_ on: Bool, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        // Reversible and never unreadable, so (like set-main) it applies directly without the revert gate.
        _ = await observer.setMirroring(of: cgID, enabled: on)
        await refresh()
    }

    /// Sets a display's software (gamma) dim, 0.15...1 where 1 = no dim. Works on any display.
    func setSoftwareDim(_ level: Float, for observation: DisplayObservation) {
        guard let cgID = observation.cgDisplayID else { return }
        softwareDim[observation.recordID] = level
        observer.setGammaDim(level, for: cgID)
    }

    /// Displays currently blacked out (gamma driven to zero — the panel stays logically connected so it
    /// can be restored instantly). Reversible and public-API-safe; gamma also resets on display
    /// reconfiguration, wake, and logout, so a blackout can never strand a surface.
    @Published private(set) var blackedOut: Set<DisplayRecordID> = []

    /// True when the display is currently blacked out.
    func isBlackedOut(_ observation: DisplayObservation) -> Bool {
        blackedOut.contains(observation.recordID)
    }

    /// Toggles Black Out: drive gamma to zero, or restore the display's effective dim level.
    func toggleBlackOut(for observation: DisplayObservation) {
        guard let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        if blackedOut.contains(id) {
            blackedOut.remove(id)
            observer.setGammaDim(softwareDim[id] ?? 1.0, for: cgID)
        } else {
            blackedOut.insert(id)
            observer.setGammaDim(0.0, for: cgID)
        }
    }

    /// Read-only display metadata (EDID-derived) for the menu's info panel.
    func displayInfo(for observation: DisplayObservation) -> [(label: String, value: String)] {
        guard let cgID = observation.cgDisplayID else { return [] }
        var info: [(String, String)] = [
            ("Name", displayName(for: observation)),
            ("Type", observation.displayClass == .builtIn ? "Built-in" : "External"),
        ]
        let vendor = CGDisplayVendorNumber(cgID)
        let model = CGDisplayModelNumber(cgID)
        let serial = CGDisplaySerialNumber(cgID)
        if vendor != 0, vendor != 0xFFFF_FFFF { info.append(("Vendor", String(vendor))) }
        if model != 0, model != 0xFFFF_FFFF { info.append(("Model", String(model))) }
        if serial != 0 { info.append(("Serial", String(serial))) }
        if let mode = observation.mode {
            info.append(("Native", "\(mode.pixelWidth) × \(mode.pixelHeight)"))
            info.append(("Refresh", "\(Int(mode.refreshHz.rounded())) Hz"))
        }
        let size = CGDisplayScreenSize(cgID)
        if size.width > 0, size.height > 0 {
            let inches = (size.width * size.width + size.height * size.height).squareRoot() / 25.4
            info.append(("Size", String(format: "%.1f-inch", inches)))
        }
        return info
    }

    /// Applies a saved scene's positions + modes to the current displays (user-triggered).
    func applyScene(_ scene: Scene) async {
        let snapshot = await observer.currentSnapshot()
        var targets: [CoreGraphicsProvider.ArrangementTarget] = []
        var rotationSkipped = false
        for member in scene.members {
            guard let observation = resolveSceneMember(member.selector, in: snapshot),
                  let cgID = observation.cgDisplayID else { continue }
            // Rotation writes aren't safely supported — skip the property but still apply the rest,
            // surfacing a non-fatal note (PRD: scenes apply everything they safely can).
            if let wanted = member.desired.rotation, wanted != observation.rotation { rotationSkipped = true }
            targets.append(.init(displayID: cgID, origin: member.desired.position, mode: member.desired.mode))
        }
        _ = observer.applyArrangement(targets)
        await refresh()
        sceneWarning = rotationSkipped
            ? "Applied. Rotation in this scene was skipped — not supported on this macOS version."
            : nil
    }

    func deleteScene(_ scene: Scene) async {
        guard let sceneLibrary else { return }
        await sceneLibrary.delete(id: scene.id)
        scenes = await sceneLibrary.all()
    }

    /// Resolves a scene member selector to a current observation (id:/alias:/tag:/main/builtin).
    private func resolveSceneMember(_ selector: String, in snapshot: TopologySnapshot) -> DisplayObservation? {
        if selector.hasPrefix("id:") {
            return snapshot.observation(for: DisplayRecordID(rawValue: String(selector.dropFirst("id:".count))))
        }
        if selector.hasPrefix("alias:") {
            let alias = String(selector.dropFirst("alias:".count))
            if let id = records.first(where: { $0.value.alias == alias })?.key { return snapshot.observation(for: id) }
        }
        if selector.hasPrefix("tag:") {
            let tag = String(selector.dropFirst("tag:".count))
            if let id = records.first(where: { $0.value.tags.contains(tag) })?.key { return snapshot.observation(for: id) }
        }
        if selector == "main" { return snapshot.observations.first { $0.isMain } }
        if selector == "builtin" { return snapshot.observations.first { $0.displayClass == .builtIn } }
        return nil
    }

    /// Sets the user alias for a display and re-resolves so the change shows immediately.
    func setAlias(_ alias: String, for observation: DisplayObservation) async {
        guard let registry, let record = records[observation.recordID] else { return }
        await registry.setAlias(alias, for: record.id)
        await refresh()
    }

    /// Drops cached control values (brightness, DDC, ICC, dim) for displays that are no longer present,
    /// so a reconnected display re-reads fresh state instead of showing a stale cached value. Only
    /// reassigns a cache when it actually has a stale key, to avoid needless UI invalidation.
    private func pruneControlCaches(to ids: Set<DisplayRecordID>) {
        if !brightness.keys.allSatisfy(ids.contains) { brightness = brightness.filter { ids.contains($0.key) } }
        if !brightnessMethod.keys.allSatisfy(ids.contains) { brightnessMethod = brightnessMethod.filter { ids.contains($0.key) } }
        if !ddcControlLevel.keys.allSatisfy(ids.contains) { ddcControlLevel = ddcControlLevel.filter { ids.contains($0.key) } }
        if !colorPreset.keys.allSatisfy(ids.contains) { colorPreset = colorPreset.filter { ids.contains($0.key) } }
        if !inputSource.keys.allSatisfy(ids.contains) { inputSource = inputSource.filter { ids.contains($0.key) } }
        if !colorProfileName.keys.allSatisfy(ids.contains) { colorProfileName = colorProfileName.filter { ids.contains($0.key) } }
        if !softwareDim.keys.allSatisfy(ids.contains) { softwareDim = softwareDim.filter { ids.contains($0.key) } }
        if !colorProfileControllable.keys.allSatisfy(ids.contains) { colorProfileControllable = colorProfileControllable.filter { ids.contains($0.key) } }
        if !blackedOut.allSatisfy(ids.contains) { blackedOut = blackedOut.filter(ids.contains) }
        #if !PUBLIC_API_ONLY
        pruneDDCCaches(to: ids)
        #endif
    }

    #if !PUBLIC_API_ONLY
    /// Releases DDC infrastructure (controllers + their retained IOAVService handles, coalescing maps,
    /// and writer tasks) for displays no longer present, so handles don't accumulate across reconnect
    /// cycles. Writer tasks are cancelled before their controller is dropped so a draining task can't
    /// re-acquire and recreate a removed entry; controllers are lazily rebuilt on next use.
    private func pruneDDCCaches(to ids: Set<DisplayRecordID>) {
        for (id, task) in ddcWriters where !ids.contains(id) { task.cancel(); ddcWriters[id] = nil }
        for (id, task) in inputSourceWriter where !ids.contains(id) { task.cancel(); inputSourceWriter[id] = nil }
        for (id, task) in colorPresetWriter where !ids.contains(id) { task.cancel(); colorPresetWriter[id] = nil }
        for (key, task) in ddcControlWriter where !ids.contains(key.id) { task.cancel(); ddcControlWriter[key] = nil }
        for (id, task) in ddcBuilders where !ids.contains(id) { task.cancel(); ddcBuilders[id] = nil }
        ddc = ddc.filter { ids.contains($0.key) }
        brightnessMax = brightnessMax.filter { ids.contains($0.key) }
        ddcTarget = ddcTarget.filter { ids.contains($0.key) }
        inputSourceTarget = inputSourceTarget.filter { ids.contains($0.key) }
        colorPresetTarget = colorPresetTarget.filter { ids.contains($0.key) }
        ddcControlMax = ddcControlMax.filter { ids.contains($0.key.id) }
        ddcControlTarget = ddcControlTarget.filter { ids.contains($0.key.id) }
        ddcProbe = ddcProbe.filter { ids.contains($0.key) }
        if !adaptiveStates.keys.allSatisfy(ids.contains) {
            adaptiveStates = adaptiveStates.filter { ids.contains($0.key) }
        }
    }
    #endif

    func refresh() async {
        var snapshot = await observer.currentSnapshot()
        // Another display-manager app (e.g. BetterDisplay) holding a reconfiguration can make
        // enumeration transiently empty or error; a Mac running this app always has ≥1 display, so
        // re-poll briefly before trusting an empty list — otherwise the menu blanks out entirely.
        var attempts = 0
        while snapshot.observations.isEmpty && attempts < 8 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            snapshot = await observer.currentSnapshot()
            attempts += 1
        }
        displays = snapshot.observations.sorted { $0.recordID.rawValue < $1.recordID.rawValue }
        pruneControlCaches(to: Set(displays.map(\.recordID)))
        // Drop any tracked off-display that has come back on its own (e.g. re-enabled elsewhere).
        let priorOffline = managedOffline
        managedOffline.removeAll { offline in
            displays.contains { $0.recordID == offline.recordID && $0.isActive }
        }
        if managedOffline != priorOffline { persistManagedOffline() }
        // Guard against a no-op republish: the active/total count string is usually unchanged across
        // a refresh, and reassigning @Published fires objectWillChange and re-evaluates every view.
        let status = "\(snapshot.activeDisplays.count) active · \(snapshot.observations.count) total"
        if statusText != status { statusText = status }
        phase = displays.isEmpty ? .empty : .ready
        await resolveRecords(snapshot)
        await refreshDiagnostics()
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPENDISPLAY_DUMP"] != nil {
            Self.dump(snapshot)
            let names = displays.map { "cgID=\($0.cgDisplayID ?? 0) → \"\(displayName(for: $0))\"" }
                .joined(separator: ", ")
            FileHandle.standardError.write(Data("names: \(names)\n".utf8))
            if !managedOffline.isEmpty {
                let offline = managedOffline.map { "\($0.name)(cgid:\($0.cgID))" }.joined(separator: ", ")
                FileHandle.standardError.write(Data("managedOffline: \(offline)\n".utf8))
            }
        }
        #endif
    }

    // MARK: - Menu controls (Phase 1)

    /// Available resolutions for a display, de-duplicated per point-size — drives the resolution slider.
    func availableModes(for observation: DisplayObservation) -> [DisplayMode] {
        guard let cgID = observation.cgDisplayID else { return [] }
        return observer.availableModes(for: cgID)
    }

    /// Every mode (un-deduped) for a display — the detail view caches this once per display and filters
    /// it locally for the resolution list, refresh rates, and HiDPI toggle, avoiding three separate
    /// CGDisplayCopyAllDisplayModes enumerations per render.
    func allModes(for observation: DisplayObservation) -> [DisplayMode] {
        guard let cgID = observation.cgDisplayID else { return [] }
        return observer.allModes(for: cgID)
    }

    /// Resolves and caches the best brightness route for a display, then reads its current level:
    /// built-in via DisplayServices (`native`), external via DDC (`hardware`), or — when neither
    /// answers — software gamma (`software`), which works on any display including DDC-less externals.
    /// This is what lets the popover show a single, always-usable brightness slider.
    func refreshBrightness(for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        #if !PUBLIC_API_ONLY
        if observation.displayClass == .builtIn {
            // DisplayServices is private SPI with a blocking IPC round-trip — read it off the main actor.
            let control = brightnessControl
            if let value = await Task.detached(priority: .userInitiated, operation: {
                control.brightness(for: cgID)
            }).value {
                brightness[id] = value
                brightnessMethod[id] = .native
                return
            }
        } else if let controller = await ddcController(for: observation) {
            // The probe tracker keeps a DDC-less external from paying the full retried read
            // (~0.7s) on every refresh before falling back to gamma — after a couple of failures
            // it goes straight to software, rechecking hardware only occasionally. The controller
            // is resolved BEFORE admitProbe: admitProbe is mutating (it spends the periodic
            // recheck token), so consuming it and then bailing on a nil controller would silently
            // push hardware rediscovery a whole recheck interval further out.
            let vcp = ExternalDisplayDDC.Feature.brightness.rawValue
            if ddcProbe[id, default: DDCProbeTracker()].admitProbe(vcp) {
                if let reading = await controller.read(vcp: vcp), reading.max > 0 {
                    ddcProbe[id, default: DDCProbeTracker()].recordSuccess(vcp)
                    // Hardware brightness just (re)appeared — lift any leftover software-gamma dim
                    // from the fallback era, or the two dimming layers stack and the panel stays
                    // dark no matter where the (now hardware) slider sits. Never while Black Out
                    // holds the panel at gamma 0 — a background refresh must not light it up.
                    if let dim = softwareDim[id], dim < 1.0, !blackedOut.contains(id) {
                        observer.setGammaDim(1.0, for: cgID)
                        softwareDim[id] = nil
                    }
                    brightness[id] = Float(reading.current) / Float(reading.max)
                    brightnessMax[id] = reading.max
                    brightnessMethod[id] = .hardware
                    return
                }
                ddcProbe[id, default: DDCProbeTracker()].recordFailure(vcp)
            }
        }
        #endif
        // Universal fallback: software gamma is public Core Graphics and works on every display.
        brightnessMethod[id] = .software
        brightness[id] = softwareDim[id] ?? 1.0
    }

    /// The caption for a display's brightness slider ("Hardware · DDC", "Software · gamma"), or nil for
    /// native control where no qualifier is needed.
    func brightnessCaption(for observation: DisplayObservation) -> String? {
        brightnessMethod[observation.recordID]?.caption
    }

    /// Sets a display's brightness (0...1) through whichever route was resolved for it, updating the
    /// cache optimistically. Native writes are immediate; DDC writes are coalesced so a fast slider
    /// drag never floods the I2C bus; the software route maps onto gamma dimming with a usable floor.
    func setBrightness(_ value: Float, for observation: DisplayObservation) {
        guard let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        brightness[id] = value
        #if PUBLIC_API_ONLY
        let method = BrightnessMethod.software
        #else
        let method = brightnessMethod[id] ?? (observation.displayClass == .builtIn ? .native : .hardware)
        #endif
        switch method {
        case .native:
            #if !PUBLIC_API_ONLY
            // Private DisplayServices SPI off the main actor; the optimistic cache is already updated.
            // DisplayServices is fast IPC (unlike slow I2C), so a fire-and-forget per tick is fine —
            // no DDC-style coalescing needed.
            let control = brightnessControl
            Task.detached(priority: .userInitiated) { _ = control.setBrightness(value, for: cgID) }
            #endif
        case .hardware:
            #if !PUBLIC_API_ONLY
            // A user-initiated change on a synced display teaches Adaptive Display: learn the
            // offset (or the schedule adoption anchor in clamshell) and start the cooldown, so
            // adaptive yields instead of fighting the slider. The adaptive loop's own writes go
            // through `applyAdaptiveBrightness`, never here.
            noteManualBrightnessForAdaptive(value, id: id)
            ddcTarget[id] = Int((value * Float(brightnessMax[id] ?? 100)).rounded())
            if ddcWriters[id] == nil {
                ddcWriters[id] = Task { [weak self] in await self?.drainDDCWrites(id, observation) }
            }
            #endif
        case .software:
            let gamma = max(0.15, value)
            softwareDim[id] = gamma
            observer.setGammaDim(gamma, for: cgID)
        }
        presentOSD(kind: .brightness, value: value, for: observation)  // Batch-3 #4
    }

    #if !PUBLIC_API_ONLY
    /// Returns (and caches) the DDC controller for an external display, building it OFF the main actor
    /// — `ExternalDisplayDDC.init` does `dlopen` + IOKit registry enumeration, which must not run on
    /// the UI thread when a display row first expands. Concurrent first-uses await one shared build,
    /// so a display can't end up with two bound IOAVService handles.
    private func ddcController(for observation: DisplayObservation) async -> ExternalDisplayDDC? {
        let id = observation.recordID
        if let existing = ddc[id] { return existing }
        if let building = ddcBuilders[id] { return await building.value }
        guard let cgID = observation.cgDisplayID else { return nil }
        let builder = Task.detached(priority: .utility) { ExternalDisplayDDC(displayID: cgID) }
        ddcBuilders[id] = builder
        let controller = await builder.value
        ddcBuilders[id] = nil
        if let controller { ddc[id] = controller }
        return controller
    }

    private func drainDDCWrites(_ id: DisplayRecordID, _ observation: DisplayObservation) async {
        guard let controller = await ddcController(for: observation) else { ddcWriters[id] = nil; return }
        while let target = ddcTarget[id] {
            ddcTarget[id] = nil
            await controller.write(.brightness, target)
        }
        ddcWriters[id] = nil
    }
    #endif

    /// Cached level (0...1) of a DDC hardware control, or nil if the display doesn't report it.
    func ddcControl(_ control: HardwareControl, for observation: DisplayObservation) -> Float? {
        ddcControlLevel[observation.recordID]?[control.vcp]
    }

    /// Forgets the DDC negative-probe cache for one display (or all). Called when the world may have
    /// changed under the cache — a topology event (hotplug, wake, monitor power-cycle) or the user
    /// deliberately opening a display's detail pane — so a monitor whose DDC just came back (e.g.
    /// power-cycled out of a wedged scaler state) regains hardware control on the *next* refresh
    /// instead of waiting out the tracker's periodic recheck. The menu-bar popover keeps using the
    /// cache, so the cheap fast path stays cheap.
    func resetDDCProbeCache(for id: DisplayRecordID? = nil) {
        #if !PUBLIC_API_ONLY
        if let id { ddcProbe[id] = nil } else { ddcProbe = [:] }
        #endif
    }

    /// Pane-open variant of `resetDDCProbeCache`: forgets the negative cache ONLY when the display
    /// currently shows no working hardware control at all. A healthy display keeps its knowledge —
    /// wiping it on every pane open would re-pay the full probe ladder (~0.75s per absent feature,
    /// serially) each time; a fully-dead one is exactly the recovery case the reset exists for
    /// (monitor power-cycled out of a wedged state), and there the re-probe cost was being paid
    /// anyway. The tracker's periodic recheck covers the in-between (some controls lost, not all).
    func retryDDCDiscoveryIfDead(for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        let id = observation.recordID
        let hasWorkingControl = !(ddcControlLevel[id] ?? [:]).isEmpty || brightnessMethod[id] == .hardware
        if !hasWorkingControl { ddcProbe[id] = nil }
        #endif
    }

    /// Whether the display advertises a VCP feature in its DDC capabilities (Batch-2 #1). **Fail-open:**
    /// if capabilities haven't been read (or the panel didn't return any), returns true so nothing is
    /// hidden just because discovery hasn't happened — capabilities only ever *remove* dead controls.
    func ddcSupports(_ vcp: UInt8, for observation: DisplayObservation) -> Bool {
        guard let caps = ddcCapabilities[observation.recordID] else { return true }
        return caps.supports(vcp)
    }

    /// Reads + caches the display's DDC capabilities string (VCP 0xF3) once per external display.
    ///
    /// ⚠️ EXPLICIT / DIAGNOSTIC USE ONLY — do NOT call from the control-refresh path. The multi-chunk
    /// `0xF3` read desynchronizes DDC/CI on some panels (Samsung S34J55x: it leaves the panel replaying a
    /// stale reply buffer so every later read returns garbage and writes are ignored until a power-cycle).
    /// Controls are fail-open without it (`ddcSupports` returns true when uncached), so the only thing
    /// lost by not calling this is hiding genuinely-unsupported controls.
    func refreshCapabilities(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn, ddcCapabilities[observation.recordID] == nil,
              let controller = await ddcController(for: observation),
              let raw = await controller.readCapabilitiesString(),
              let caps = DDCCapabilities.parse(raw) else { return }
        ddcCapabilities[observation.recordID] = caps
        #endif
    }

    /// Reads every hardware (DDC) control for an external display into the cache. Skips the built-in,
    /// anything the capabilities string says is unsupported (when known — `ddcSupports` is fail-open),
    /// and any feature the panel doesn't read back. No-op in the public-API-only build.
    ///
    /// NOTE: this deliberately does NOT auto-read the `0xF3` capabilities string. That multi-chunk read
    /// desynchronizes DDC/CI on some panels (e.g. Samsung S34J55x), wedging *all* subsequent reads — it
    /// is now an explicit, diagnostic-only path (CLI `ddc … caps`). See `refreshCapabilities`.
    func refreshHardwareControls(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn, let controller = await ddcController(for: observation) else { return }
        let id = observation.recordID
        for control in HardwareControl.allCases {
            let vcp = control.vcp
            guard ddcSupports(vcp, for: observation),
                  ddcProbe[id, default: DDCProbeTracker()].admitProbe(vcp) else { continue }
            if let reading = await controller.read(vcp: vcp), reading.max > 0 {
                ddcProbe[id, default: DDCProbeTracker()].recordSuccess(vcp)
                ddcControlLevel[id, default: [:]][vcp] = Float(reading.current) / Float(reading.max)
                ddcControlMax[DDCControlKey(id: id, vcp: vcp)] = reading.max
            } else {
                ddcProbe[id, default: DDCProbeTracker()].recordFailure(vcp)
            }
        }
        #endif
    }

    /// Sets a DDC hardware control (0...1), updating the cache optimistically and coalescing the
    /// I2C writes the same way brightness does.
    func setHardwareControl(_ control: HardwareControl, _ value: Float, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn else { return }
        let id = observation.recordID
        let key = DDCControlKey(id: id, vcp: control.vcp)
        ddcControlLevel[id, default: [:]][control.vcp] = value
        ddcControlTarget[key] = Int((value * Float(ddcControlMax[key] ?? 100)).rounded())
        if ddcControlWriter[key] == nil {
            ddcControlWriter[key] = Task { [weak self] in await self?.drainHardwareWrites(key, control, observation) }
        }
        if control == .volume { presentOSD(kind: .volume, value: value, for: observation) }  // Batch-3 #4
        #endif
    }

    #if !PUBLIC_API_ONLY
    private func drainHardwareWrites(_ key: DDCControlKey, _ control: HardwareControl, _ observation: DisplayObservation) async {
        guard let controller = await ddcController(for: observation) else { ddcControlWriter[key] = nil; return }
        while let target = ddcControlTarget[key] {
            ddcControlTarget[key] = nil
            await controller.write(vcp: key.vcp, target)
        }
        ddcControlWriter[key] = nil
    }
    #endif

    /// Reads the external display's current DDC input source into the cache.
    func refreshInputSource(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        let id = observation.recordID
        let vcp = ExternalDisplayDDC.Feature.inputSource.rawValue
        // Controller before admitProbe — admitProbe spends the periodic recheck token (see
        // refreshBrightness), so it must only run when a probe can actually happen.
        guard observation.displayClass != .builtIn,
              let controller = await ddcController(for: observation),
              ddcProbe[id, default: DDCProbeTracker()].admitProbe(vcp) else { return }
        guard let reading = await controller.read(vcp: vcp) else {
            ddcProbe[id, default: DDCProbeTracker()].recordFailure(vcp)
            return
        }
        ddcProbe[id, default: DDCProbeTracker()].recordSuccess(vcp)
        inputSource[id] = reading.current
        #endif
    }

    /// Switches the external display's DDC input source to `code` (e.g. HDMI/DisplayPort). User-driven.
    /// Coalesced through a single per-display writer (like brightness/contrast) so rapid selections
    /// settle the panel on the last choice and can't reorder on the shared I2C bus.
    func setInputSource(_ code: Int, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn else { return }
        let id = observation.recordID
        inputSource[id] = code
        inputSourceTarget[id] = code
        if inputSourceWriter[id] == nil {
            inputSourceWriter[id] = Task { [weak self] in await self?.drainInputSourceWrites(id, observation) }
        }
        #endif
    }

    #if !PUBLIC_API_ONLY
    private func drainInputSourceWrites(_ id: DisplayRecordID, _ observation: DisplayObservation) async {
        guard let controller = await ddcController(for: observation) else { inputSourceWriter[id] = nil; return }
        while let target = inputSourceTarget[id] {
            inputSourceTarget[id] = nil
            await controller.write(.inputSource, target)
        }
        inputSourceWriter[id] = nil
    }
    #endif

    /// Sends a DDC power-mode command (VCP 0xD6) to an external display (Issue 1). Best-effort and
    /// fire-and-forget: the panel may NAK or ignore the write, and many displays cannot be woken back
    /// On over DDC once powered Off — none of that is treated as an error. No-op on the built-in and in
    /// the public-API-only build (DDC uses private SPI). The audit/safety path is untouched because a
    /// power command doesn't alter the logical arrangement.
    func setPowerMode(_ mode: DDCPowerMode, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn else { return }
        Task { [weak self] in
            guard let controller = await self?.ddcController(for: observation) else { return }
            await controller.write(.power, mode.vcpValue)
        }
        #endif
    }

    /// Refreshes a display's cached ICC state — controllability, current profile name, and (once) the
    /// installed-profile list — all OFF the main actor, since ColorSync iterates and parses profiles
    /// from disk. The menu reads only the published caches and never touches ColorSync in a view body.
    func refreshColorProfile(for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        let needProfiles = availableColorProfilesCache.isEmpty
        let result = await Task.detached(priority: .userInitiated) {
            (controllable: ColorProfileService.isControllable(cgID),
             name: ColorProfileService.currentProfileName(for: cgID),
             profiles: needProfiles ? ColorProfileService.availableProfiles() : nil)
        }.value
        colorProfileControllable[id] = result.controllable
        colorProfileName[id] = result.name
        if let profiles = result.profiles { availableColorProfilesCache = profiles }
    }

    /// Assigns an ICC profile to a display (validated by ColorSyncProfileVerify inside the service),
    /// then re-reads the applied name off-main ("verify, don't assume"). User-driven.
    func setColorProfile(_ profile: ICCProfile, for observation: DisplayObservation) async {
        guard FeatureFlags.iccProfileWrite, let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        let name = await Task.detached(priority: .userInitiated) { () -> String? in
            ColorProfileService.setProfile(profile, for: cgID)
            return ColorProfileService.currentProfileName(for: cgID)
        }.value
        colorProfileName[id] = name
        reapplySoftwareDim(for: observation)
    }

    /// Reverts a display to its factory ICC profile, then re-reads the resulting name off-main.
    func resetColorProfile(for observation: DisplayObservation) async {
        guard FeatureFlags.iccProfileWrite, let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        let name = await Task.detached(priority: .userInitiated) { () -> String? in
            ColorProfileService.resetToFactory(for: cgID)
            return ColorProfileService.currentProfileName(for: cgID)
        }.value
        colorProfileName[id] = name
        reapplySoftwareDim(for: observation)
    }

    /// Re-asserts an active software-gamma dim after a colour-profile change. Applying a profile can
    /// rebuild the display's transfer tables WindowServer-side, silently wiping a formula-based dim —
    /// the screen would jump to full brightness while the slider still shows the dimmed level.
    /// Skipped while Black Out holds the panel at gamma 0: dim < blackout, re-asserting would light it.
    private func reapplySoftwareDim(for observation: DisplayObservation) {
        guard let cgID = observation.cgDisplayID, !blackedOut.contains(observation.recordID),
              let dim = softwareDim[observation.recordID], dim < 1.0 else { return }
        observer.setGammaDim(dim, for: cgID)
    }

    /// Current rotation of a display in degrees (0/90/180/270), read via public Core Graphics.
    func currentRotation(for observation: DisplayObservation) -> Int {
        guard let cgID = observation.cgDisplayID else { return 0 }
        return rotationBackend.currentRotation(for: cgID)
    }

    /// The reason rotation writes are unavailable (drives the read-only UI label), or nil if writable.
    var rotationUnavailableReason: String? {
        if case .unavailable(let reason) = rotationBackend.capability { return reason }
        return nil
    }

    /// Whether rotation writes are available (the experimental backend is enabled).
    var rotationWritable: Bool {
        if case .experimental = rotationBackend.capability { return true }
        return false
    }

    /// Rotates a display (experimental path). Writes a recovery marker first so a stranded layout is
    /// detected + recovered on next launch; on failure runs Reconnect All; clears the marker after.
    func setRotation(_ degrees: Int, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        busy = true
        defer { busy = false }
        let safeAngle = rotationBackend.currentRotation(for: cgID)
        Self.writeRotationMarker(RotationMarker(cgID: cgID, safeAngle: safeAngle))
        do {
            try await rotationBackend.setRotation(degrees, for: cgID)
        } catch {
            // The helper validates + rolls back itself, but ensure the safe angle is restored and a
            // safe surface remains even if the helper died before its own rollback.
            try? await rotationBackend.setRotation(safeAngle, for: cgID)
            _ = await coordinator.reconnectAll()
        }
        Self.clearRotationMarker()
        await refresh()
    }

    /// Pending-rotation marker: records which display was being rotated and the angle it was at before,
    /// so that if the app/helper dies mid-rotation, the next launch can restore that exact safe angle.
    private struct RotationMarker: Codable { let cgID: CGDirectDisplayID; let safeAngle: Int }

    private static func rotationMarkerURL() -> URL? {
        (try? DiskCheckpointStore.defaultDirectory())?.appendingPathComponent("rotation.pending")
    }
    private static func writeRotationMarker(_ marker: RotationMarker) {
        guard let url = rotationMarkerURL(), let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private static func readRotationMarker() -> RotationMarker? {
        guard let url = rotationMarkerURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RotationMarker.self, from: data)
    }
    private static func clearRotationMarker() {
        if let url = rotationMarkerURL() { try? FileManager.default.removeItem(at: url) }
    }

    /// Opens System Settings → Displays — the supported way to rotate on this macOS.
    func openDisplaySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.displays",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// The colour-preset codes to offer for a display. VCP 0x14 (Select Color Preset) is a
    /// **non-continuous** enum: the panel only honours the specific values it advertises in its DDC
    /// capabilities, so we offer those (when known) rather than a contiguous 1...max range — otherwise
    /// most selections are codes the monitor silently ignores and the control appears to "do nothing".
    /// Falls back to 1...max only when capabilities haven't been read.
    func colorPresetCodes(for observation: DisplayObservation) -> [Int] {
        DDCCapabilities.offeredValues(
            ddcCapabilities[observation.recordID], for: 0x14,
            fallbackMax: colorPresetMax[observation.recordID] ?? 5)
    }

    /// Reads the external display's current DDC colour preset (VCP 0x14) + its max code into the cache.
    /// Does NOT auto-fetch the capabilities string (it wedges some panels — see `refreshHardwareControls`);
    /// `colorPresetCodes` falls back to a 1...max menu when capabilities aren't cached.
    func refreshColorPreset(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        let id = observation.recordID
        let vcp = ExternalDisplayDDC.Feature.colorPreset.rawValue
        // Controller before admitProbe — see refreshInputSource.
        guard observation.displayClass != .builtIn,
              let controller = await ddcController(for: observation),
              ddcProbe[id, default: DDCProbeTracker()].admitProbe(vcp) else { return }
        guard let reading = await controller.read(vcp: vcp) else {
            ddcProbe[id, default: DDCProbeTracker()].recordFailure(vcp)
            return
        }
        ddcProbe[id, default: DDCProbeTracker()].recordSuccess(vcp)
        colorPreset[id] = reading.current
        colorPresetMax[id] = max(reading.max, 1)
        #endif
    }

    /// Sets the external display's DDC colour preset (sRGB / colour-temperature / native). User-driven.
    /// Coalesced per display (like input source) so rapid taps settle on the last choice in order.
    func setColorPreset(_ code: Int, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn else { return }
        let id = observation.recordID
        // A user-picked preset during an adaptive evening is adopted for the rest of the phase
        // (one-night adoption) — the policy stops issuing preset writes until the next transition.
        if settings.adaptiveWarmthEnabled {
            adaptiveStates[id] = AdaptiveDisplayPolicy.noteManualPreset(
                state: adaptiveStates[id] ?? seededAdaptiveState(for: id))
        }
        colorPreset[id] = code
        colorPresetTarget[id] = code
        if colorPresetWriter[id] == nil {
            colorPresetWriter[id] = Task { [weak self] in await self?.drainColorPresetWrites(id, observation) }
        }
        #endif
    }

    #if !PUBLIC_API_ONLY
    private func drainColorPresetWrites(_ id: DisplayRecordID, _ observation: DisplayObservation) async {
        guard let controller = await ddcController(for: observation) else { colorPresetWriter[id] = nil; return }
        while let target = colorPresetTarget[id] {
            colorPresetTarget[id] = nil
            await controller.write(.colorPreset, target)
        }
        colorPresetWriter[id] = nil
    }

    // MARK: - Adaptive Display (Labs): brightness sync + evening warmth

    /// Idempotent start/stop of the adaptive sampling loop — runs only while a feature toggle is on
    /// AND an active external exists (mirrors `reconcileMediaKeyTap`/`reconcileDisplaySleepGuard`).
    /// 5s cadence: one cheap DisplayServices IPC per tick; slower would visibly lag the built-in
    /// panel animating right next to the external, faster buys nothing through the 0.02 hysteresis.
    func reconcileAdaptiveLoop() {
        let wantRunning = (settings.adaptiveBrightnessSyncEnabled || settings.adaptiveWarmthEnabled)
            && displays.contains { $0.isActive && $0.displayClass != .builtIn }
        if wantRunning {
            guard adaptiveLoop == nil else { return }
            adaptiveLoop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.adaptiveTick()
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        } else {
            adaptiveLoop?.cancel()
            adaptiveLoop = nil
        }
    }

    /// One adaptive pass: sample the world once (built-in brightness, Night Shift, clock), then let
    /// the pure `AdaptiveDisplayPolicy` decide per display and apply its Decision in the required
    /// order — persist the day-preset memory BEFORE the preset write (restore-owed invariant),
    /// then preset, then the memory clear, then brightness.
    private func adaptiveTick() async {
        let config = settings.adaptiveConfig
        let syncOn = settings.adaptiveBrightnessSyncEnabled
        let warmthOn = settings.adaptiveWarmthEnabled
        guard syncOn || warmthOn else { return }

        let builtInObs = displays.first { $0.displayClass == .builtIn && $0.isActive }
        var builtInSample: Float?
        if syncOn, let builtIn = builtInObs, let builtInCG = builtIn.cgDisplayID {
            let control = brightnessControl
            builtInSample = await Task.detached(priority: .utility) { control.brightness(for: builtInCG) }.value
            // Keep the built-in's own slider live too — macOS auto-brightness moves it under us.
            if let sample = builtInSample, abs((brightness[builtIn.recordID] ?? -1) - sample) > 0.004 {
                brightness[builtIn.recordID] = sample
            }
        }
        if syncOn, builtInObs == nil {
            // Built-in off: read the ambient light sensor directly (lid-open-display-off setups —
            // the sensor keeps reporting even though macOS drives no panel from it). EMA-smoothed;
            // an unreadable sensor (lid actually closed) clears it → schedule mode.
            let reader = ambientLight
            if let sample = await Task.detached(priority: .utility) { reader.lux() }.value {
                ambientLuxEMA = ambientLuxEMA.map { $0 * 0.6 + sample * 0.4 } ?? sample
            } else {
                ambientLuxEMA = nil
            }
        } else {
            ambientLuxEMA = nil  // built-in active (or sync off): ambient mode dormant
        }
        var nightShiftActive: Bool?
        if warmthOn {
            let reader = nightShift
            nightShiftActive = await Task.detached(priority: .utility) { reader.isActive() }.value
        }
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        for observation in displays where observation.displayClass != .builtIn && observation.isActive {
            guard let cgID = observation.cgDisplayID else { continue }
            let id = observation.recordID
            // Resolve capabilities lazily, once — the caches are sticky and pruned on disconnect.
            if brightnessMethod[id] == nil { await refreshBrightness(for: observation) }
            guard brightnessMethod[id] == .hardware else { continue }  // DDC-safety gate
            if warmthOn, colorPreset[id] == nil { await refreshColorPreset(for: observation) }

            let state = adaptiveStates[id] ?? seededAdaptiveState(for: id)
            let input = AdaptiveDisplayPolicy.Input(
                now: now, minuteOfDay: minuteOfDay,
                builtInPresent: builtInObs != nil,
                builtInBrightness: builtInSample,
                ambientLux: ambientLuxEMA,
                displayAsleep: CGDisplayIsAsleep(cgID) != 0,
                currentPreset: colorPreset[id],
                dayPreset: settings.adaptiveDayPresetByDisplay[id.rawValue],
                nightShiftActive: nightShiftActive,
                brightnessSyncEnabled: syncOn, warmthEnabled: warmthOn)
            let decision = AdaptiveDisplayPolicy.evaluate(input, config: config, state: state)

            if let dayPreset = decision.rememberDayPreset {
                settings.adaptiveDayPresetByDisplay[id.rawValue] = dayPreset
                persistSettings()  // BEFORE the evening write — a crash between must still owe a restore
            }
            if let preset = decision.presetWrite { applyAdaptivePreset(preset, for: observation) }
            if decision.clearDayPreset {
                settings.adaptiveDayPresetByDisplay[id.rawValue] = nil
                persistSettings()
            }
            if let value = decision.brightnessWrite { applyAdaptiveBrightness(value, for: observation) }
            // Learned offsets persist at tick-time, not per slider move — no disk spam mid-drag.
            if settings.adaptiveBrightnessOffsetByDisplay[id.rawValue] != decision.state.brightnessOffset {
                settings.adaptiveBrightnessOffsetByDisplay[id.rawValue] = decision.state.brightnessOffset
                persistSettings()
            }
            adaptiveStates[id] = decision.state
        }
    }

    /// First state for a display: carry the learned offset across relaunches.
    private func seededAdaptiveState(for id: DisplayRecordID) -> AdaptiveDisplayPolicy.DisplayState {
        AdaptiveDisplayPolicy.DisplayState(
            brightnessOffset: settings.adaptiveBrightnessOffsetByDisplay[id.rawValue] ?? 0)
    }

    /// OSD-silent adaptive brightness apply: cache + coalesced DDC write, NO OSD flash and NO
    /// manual-change note — this is the machine's hand, not the user's. (`setBrightness` is the
    /// user funnel and does both.)
    private func applyAdaptiveBrightness(_ value: Float, for observation: DisplayObservation) {
        let id = observation.recordID
        brightness[id] = value  // keep the visible slider honest
        ddcTarget[id] = Int((value * Float(brightnessMax[id] ?? 100)).rounded())
        if ddcWriters[id] == nil {
            ddcWriters[id] = Task { [weak self] in await self?.drainDDCWrites(id, observation) }
        }
    }

    /// OSD-silent adaptive preset apply. Updates the cache first so the policy's drift detection
    /// doesn't mistake our own write for a monitor-button change on the next tick.
    private func applyAdaptivePreset(_ code: Int, for observation: DisplayObservation) {
        let id = observation.recordID
        colorPreset[id] = code
        colorPresetTarget[id] = code
        if colorPresetWriter[id] == nil {
            colorPresetWriter[id] = Task { [weak self] in await self?.drainColorPresetWrites(id, observation) }
        }
    }

    /// Restores every owed daytime colour preset (quit / warmth-disable), awaited directly on the
    /// DDC controller so process exit can't race the fire-and-forget writers. Entries whose display
    /// isn't currently present stay persisted — the day-phase restore rule picks them up whenever
    /// the display returns.
    private func restoreOwedDayPresets() async {
        guard !settings.adaptiveDayPresetByDisplay.isEmpty else { return }
        var remaining = settings.adaptiveDayPresetByDisplay
        for (rawID, code) in settings.adaptiveDayPresetByDisplay {
            guard let observation = displays.first(where: { $0.recordID.rawValue == rawID }),
                  observation.isActive,
                  let controller = await ddcController(for: observation) else { continue }
            await controller.write(.colorPreset, code)
            colorPreset[observation.recordID] = code
            remaining[rawID] = nil
        }
        if remaining != settings.adaptiveDayPresetByDisplay {
            settings.adaptiveDayPresetByDisplay = remaining
            persistSettings()
        }
    }

    /// The manual-brightness note for `setBrightness`'s hardware branch (user slider/media keys on
    /// a synced external): learn the offset in sync mode, anchor the adoption in schedule mode.
    private func noteManualBrightnessForAdaptive(_ value: Float, id: DisplayRecordID) {
        guard settings.adaptiveBrightnessSyncEnabled else { return }
        let builtIn = displays.first { $0.displayClass == .builtIn && $0.isActive }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        // The offset-teaching reference is whatever adaptive is currently following: the built-in's
        // level in sync mode, the light-sensor curve in ambient mode, nothing in schedule mode.
        let reference: Float? = builtIn.flatMap { brightness[$0.recordID] }
            ?? ambientLuxEMA.map(AdaptiveDisplayPolicy.ambientLevel(forLux:))
        adaptiveStates[id] = AdaptiveDisplayPolicy.noteManualBrightness(
            value,
            reference: reference,
            scheduleTarget: AdaptiveDisplayPolicy.scheduleLevel(atMinute: minute,
                                                                config: settings.adaptiveConfig),
            at: Date(),
            state: adaptiveStates[id] ?? seededAdaptiveState(for: id))
    }

    /// One-line adaptive status for the display detail card, or nil when adaptive isn't acting on
    /// this display (built-in, features off, or no hardware brightness).
    func adaptiveStatusLine(for observation: DisplayObservation) -> String? {
        guard observation.displayClass != .builtIn,
              settings.adaptiveBrightnessSyncEnabled || settings.adaptiveWarmthEnabled,
              brightnessMethod[observation.recordID] == .hardware else { return nil }
        let id = observation.recordID
        let state = adaptiveStates[id]
        var parts: [String] = []
        if settings.adaptiveBrightnessSyncEnabled {
            if let manualAt = state?.manualBrightnessAt,
               Date() < manualAt.addingTimeInterval(settings.adaptiveConfig.manualCooldown) {
                parts.append("brightness paused (manual)")
            } else if displays.contains(where: { $0.displayClass == .builtIn && $0.isActive }) {
                let offset = Int(((state?.brightnessOffset ?? 0) * 100).rounded())
                parts.append(offset == 0 ? "following built-in"
                                         : String(format: "following built-in (%+d%%)", offset))
            } else if let lux = ambientLuxEMA {
                parts.append("following room light (\(Int(lux.rounded())) lx)")
            } else {
                parts.append("on schedule (no light sensor)")
            }
        }
        if settings.adaptiveWarmthEnabled {
            parts.append(state?.warmthPhase == .evening ? "evening warmth active" : "day colour")
        }
        return "Adaptive: " + parts.joined(separator: " · ")
    }

    func setAdaptiveBrightnessSyncEnabled(_ enabled: Bool) {
        guard settings.adaptiveBrightnessSyncEnabled != enabled else { return }
        settings.adaptiveBrightnessSyncEnabled = enabled
        persistSettings()
        reconcileAdaptiveLoop()
    }

    func setAdaptiveWarmthEnabled(_ enabled: Bool) {
        guard settings.adaptiveWarmthEnabled != enabled else { return }
        settings.adaptiveWarmthEnabled = enabled
        persistSettings()
        reconcileAdaptiveLoop()
        if !enabled { Task { [weak self] in await self?.restoreOwedDayPresets() } }
    }

    func setAdaptiveEveningPreset(_ code: Int) {
        guard settings.adaptiveEveningPreset != code else { return }
        settings.adaptiveEveningPreset = code
        persistSettings()
    }

    /// The schedule-fallback brightness plateaus (0.1...1) — what clamshell mode dims between.
    func setAdaptiveFallbackLevels(day: Float, night: Float) {
        let day = min(max(day, 0.1), 1)
        let night = min(max(night, 0.1), 1)
        guard settings.adaptiveFallbackDayLevel != day
            || settings.adaptiveFallbackNightLevel != night else { return }
        settings.adaptiveFallbackDayLevel = day
        settings.adaptiveFallbackNightLevel = night
        persistSettings()
    }

    func setAdaptiveSchedule(dayStartMinute: Int, nightStartMinute: Int, transitionMinutes: Int) {
        let day = min(max(dayStartMinute, 0), 1439)
        let night = min(max(nightStartMinute, 0), 1439)
        let ramp = min(max(transitionMinutes, 1), 180)
        guard settings.adaptiveDayStartMinute != day || settings.adaptiveNightStartMinute != night
            || settings.adaptiveTransitionMinutes != ramp else { return }
        settings.adaptiveDayStartMinute = day
        settings.adaptiveNightStartMinute = night
        settings.adaptiveTransitionMinutes = ramp
        persistSettings()
    }
    #endif

    /// Applies a chosen resolution/mode behind the timed auto-revert gate (Issue 6), then re-reads the
    /// topology. A bad/blank resolution can leave a display unreadable, so the change is checkpointed
    /// and reverts itself unless confirmed within the window.
    func setMode(_ mode: DisplayMode, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        await applyWithRevert("Resolution changed on \(displayName(for: observation))") {
            _ = self.observer.applyArrangement([.init(displayID: cgID, origin: nil, mode: mode)])
        }
    }

    /// Whether `mode` is a pinned favourite for this display (Batch-2 #3).
    func isFavoriteResolution(_ mode: DisplayMode, for observation: DisplayObservation) -> Bool {
        favorites.isFavorite(mode, for: observation.recordID)
    }

    /// Pins/unpins `mode` as a favourite for this display and persists.
    func toggleFavoriteResolution(_ mode: DisplayMode, for observation: DisplayObservation) {
        favorites.toggle(mode, for: observation.recordID)
        try? favoritesStore?.save(favorites)
    }

    /// The display's favourite modes (newest first), resolved against `stops` — stale ones drop out.
    func favoriteResolutions(among stops: [DisplayMode], for observation: DisplayObservation) -> [DisplayMode] {
        let merged = favorites.merged(stops: stops, for: observation.recordID)
        let count = favorites.favoriteKeys(for: observation.recordID).count
        return Array(merged.prefix(min(count, merged.count))).filter { isFavoriteResolution($0, for: observation) }
    }

    /// Refresh rates available at the display's current resolution (same point size + HiDPI), descending.
    func refreshRates(for observation: DisplayObservation) -> [Double] {
        guard let cgID = observation.cgDisplayID, let current = observation.mode else { return [] }
        let rates = observer.allModes(for: cgID)
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight && $0.isHiDPI == current.isHiDPI }
            .map { ($0.refreshHz * 10).rounded() / 10 }
        return Array(Set(rates)).sorted(by: >)
    }

    /// Switches the refresh rate at the current resolution.
    func setRefresh(_ hz: Double, for observation: DisplayObservation) async {
        guard var target = observation.mode else { return }
        target.refreshHz = hz
        await setMode(target, for: observation)
    }

    /// True when the current resolution offers both a HiDPI (Retina) and a non-HiDPI variant.
    func hiDPIToggleAvailable(for observation: DisplayObservation) -> Bool {
        guard let cgID = observation.cgDisplayID, let current = observation.mode else { return false }
        let modes = observer.allModes(for: cgID)
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
        return modes.contains(where: { $0.isHiDPI }) && modes.contains(where: { !$0.isHiDPI })
    }

    /// Switches the current resolution between HiDPI (Retina) and non-HiDPI, keeping the best refresh.
    func setHiDPI(_ on: Bool, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID, let current = observation.mode else { return }
        let candidate = observer.allModes(for: cgID)
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight && $0.isHiDPI == on }
            .max(by: { $0.refreshHz < $1.refreshHz })
        guard let candidate else { return }
        await setMode(candidate, for: observation)
    }

    /// Makes a display the main display by re-anchoring every origin so this one sits at (0,0) —
    /// Core Graphics treats the display at the origin as main.
    /// Makes a display the main display by re-anchoring every origin so this one sits at (0,0) — Core
    /// Graphics treats the display at the origin as main, and accepts the negative origins this gives
    /// the other displays, so the physical arrangement is preserved.
    ///
    /// Applies immediately and sticks — no timed auto-revert. Changing the main display never leaves a
    /// display unreadable (both stay usable), so the revert gate (which is for bad resolutions) would
    /// only undo the user's intended change and bounce the menu bar back.
    ///
    /// The shift is computed from a **fresh** snapshot, re-resolving the target by display id: the
    /// observation handed in by the menu can carry a stale origin (cached from before the last
    /// arrangement change), which would compute a zero/wrong shift and silently no-op — exactly the
    /// "set-main does nothing / the other screen stays main" symptom.
    func setMain(for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        let snapshot = await observer.currentSnapshot()
        guard let target = snapshot.observations.first(where: { $0.cgDisplayID == cgID }),
              !target.isMain else { return }
        let dx = -target.origin.x
        let dy = -target.origin.y
        let targets = snapshot.observations.compactMap { obs -> CoreGraphicsProvider.ArrangementTarget? in
            guard let id = obs.cgDisplayID else { return nil }
            return .init(displayID: id,
                         origin: DisplayOrigin(x: obs.origin.x + dx, y: obs.origin.y + dy),
                         mode: nil)
        }
        _ = observer.applyArrangement(targets)
        await refresh()
    }

    // MARK: - Timed auto-revert safety gate (Issue 6)

    /// Countdown length for the resolution revert window (clamped to a sane minimum).
    private var arrangementRevertSeconds: Int { max(3, settings.arrangementAutoRevertSeconds) }

    /// Applies a **resolution** change behind a macOS-style timed auto-revert: snapshot the prior mode,
    /// apply, then start a "Keep these settings?" countdown that restores it unless the user confirms.
    /// Used for resolution only — a bad/blank mode can strand a display, whereas set-main and mirror
    /// never leave a display unreadable, so those apply directly (reverting them just fights the user).
    /// The auto-revert needs no input, so recovery is guaranteed even if the display became unreadable.
    private func applyWithRevert(_ message: String, _ apply: () async -> Void) async {
        // A change made while a window is still open keeps the prior one, then opens a fresh window.
        if revertGate?.isPending == true { confirmArrangementChange() }
        let before = await observer.currentSnapshot().observations
        await apply()
        await refresh()
        beginRevertWindow(before: before, message: message)
    }

    private func beginRevertWindow(before: [DisplayObservation], message: String) {
        let seconds = arrangementRevertSeconds
        revertGate = TimedRevertGate(before: before, deadline: Date().addingTimeInterval(Double(seconds)))
        revertMessage = message
        // Crash recovery: a marker (same Application Support dir the checkpoints/rotation marker use)
        // lets the next launch restore the prior arrangement if the app dies mid-window.
        Self.writeRevertMarker(before)
        pendingRevert = PendingRevert(message: message, secondsRemaining: seconds)
        // The confirmation renders in-context (menu-bar pop-out and the Settings window), both of which
        // observe `pendingRevert`. The AppKit status item ensures the pop-out is on the right screen.
        revertTask?.cancel()
        revertTask = Task { [weak self] in await self?.driveRevertCountdown() }
    }

    /// Ticks the open window ~5×/second: updates the countdown label and, at the deadline, restores
    /// the prior arrangement. Self-cancels once the gate resolves (keep or revert).
    private func driveRevertCountdown() async {
        while !Task.isCancelled {
            guard var gate = revertGate, gate.isPending else { return }
            let now = Date()
            if let before = gate.tick(now: now) {
                revertGate = gate
                await restoreArrangement(before)
                clearRevertWindow()
                return
            }
            revertGate = gate
            pendingRevert = PendingRevert(message: revertMessage, secondsRemaining: gate.secondsRemaining(now: now))
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// User accepted the change — keep it and close the window.
    func confirmArrangementChange() {
        guard var gate = revertGate, gate.confirm() else { return }
        revertGate = gate
        clearRevertWindow()
    }

    /// User asked to revert now — restore the prior arrangement and close the window.
    func revertArrangementChange() async {
        guard var gate = revertGate, let before = gate.revert() else { return }
        revertGate = gate
        await restoreArrangement(before)
        clearRevertWindow()
    }

    private func clearRevertWindow() {
        revertTask?.cancel()
        revertTask = nil
        revertGate = nil
        pendingRevert = nil
        Self.clearRevertMarker()
    }

    /// Restores each display's exact prior mode + origin (origins also restore which display is main,
    /// since Core Graphics treats the display at (0,0) as main), then its prior mirror state.
    private func restoreArrangement(_ observations: [DisplayObservation]) async {
        let targets = observations.compactMap { obs -> CoreGraphicsProvider.ArrangementTarget? in
            guard let cgID = obs.cgDisplayID else { return nil }
            return .init(displayID: cgID, origin: obs.origin, mode: obs.mode)
        }
        if !targets.isEmpty { _ = observer.applyArrangement(targets) }
        for obs in observations {
            guard let cgID = obs.cgDisplayID else { continue }
            _ = await observer.setMirroring(of: cgID, enabled: obs.isMirrored)
        }
        await refresh()
    }

    /// Pending-revert marker (mirrors the rotation marker): the prior arrangement, persisted so a
    /// crash/quit during the window doesn't strand a bad layout — the next launch restores it.
    private static func revertMarkerURL() -> URL? {
        (try? DiskCheckpointStore.defaultDirectory())?.appendingPathComponent("revert.pending")
    }
    private static func writeRevertMarker(_ observations: [DisplayObservation]) {
        guard let url = revertMarkerURL(), let data = try? JSONEncoder().encode(observations) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private static func readRevertMarker() -> [DisplayObservation]? {
        guard let url = revertMarkerURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([DisplayObservation].self, from: data)
    }
    private static func clearRevertMarker() {
        if let url = revertMarkerURL() { try? FileManager.default.removeItem(at: url) }
    }

    /// Turns a live display off (flagship). Routes through the coordinator, which preflights and
    /// refuses to remove the last active surface; on success the display is remembered as
    /// managed-offline so it keeps an "off" card in the menu. Works on any display, the built-in
    /// included, as long as another stays active.
    func setDisplayActive(_ active: Bool, for observation: DisplayObservation) async {
        guard !active else { return }  // turning back on is handled by reconnectOffline
        busy = true
        defer { busy = false }
        let offline = OfflineDisplay(
            recordID: observation.recordID,
            cgID: observation.cgDisplayID ?? 0,
            name: displayName(for: observation),
            displayClass: observation.displayClass)
        let result = try? await coordinator.disconnect(
            observation.recordID,
            options: DisconnectOptions(actor: .ui, identityConfidence: 1.0))
        if case .committed? = result {
            managedOffline.removeAll { $0.recordID == offline.recordID }
            managedOffline.append(offline)
            persistManagedOffline()
        }
        await refresh()
    }

    /// Turns a previously turned-off display back on. Reconnects by raw display id (a disabled
    /// display drops off the online list, so UUID resolution can fail), then drops it from the
    /// managed-offline list and re-reads the topology.
    func reconnectOffline(_ offline: OfflineDisplay) async {
        busy = true
        defer { busy = false }
        let reconnectID = offline.cgID != 0
            ? DisplayRecordID(rawValue: "cgid:\(offline.cgID)")
            : offline.recordID
        try? await lifecycle.reconnect(reconnectID, deadline: Date().addingTimeInterval(10))
        managedOffline.removeAll { $0.recordID == offline.recordID }
        persistManagedOffline()
        await refresh()
    }

    /// Long-lived subscription to the observer's reconfiguration events: every hotplug, unplug,
    /// sleep, or enable/disable refreshes the UI and re-checks the always-one-active invariant.
    private func observeTopologyChanges() async {
        let stream = await observer.changes()
        for await _ in stream {
            let prior = displays
            // A reconfiguration can mean a monitor was re-plugged or power-cycled — its DDC may have
            // just come back (or gone away), so any negative probe knowledge is stale.
            resetDDCProbeCache()
            await refresh()
            await enforceActiveSurfaceInvariant()
            reconcileDisplaySleepGuard()  // external arrived/left → acquire or release the keep-awake assertion
            #if !PUBLIC_API_ONLY
            reconcileAdaptiveLoop()  // externals may have arrived/left → start or stop adaptive
            #endif
            let autoDisconnected = await applyAutoDisconnectBuiltInIfNeeded()  // external arrived → built-in off
            postDisplayNotifications(prior: prior, builtInAutoDisconnected: autoDisconnected)  // Batch-2 #5
        }
    }

    /// Posts user notifications for a topology transition, per the pure `NotificationPolicy` (Batch-2 #5).
    private func postDisplayNotifications(prior: [DisplayObservation], builtInAutoDisconnected: Bool) {
        let names = Dictionary(
            (prior + displays).map { ($0.recordID, displayName(for: $0)) }, uniquingKeysWith: { _, b in b }
        )
        let notes = NotificationPolicy.notifications(
            prior: prior, current: displays, names: names,
            builtInAutoDisconnected: builtInAutoDisconnected,
            enabled: settings.displayNotificationsEnabled
        )
        for note in notes { NotificationDelivery.post(note) }
    }

    /// Toggle for display notifications (Batch-2 #5). Persists and, when turned on, requests
    /// notification authorization (the one-time system prompt).
    func setDisplayNotificationsEnabled(_ enabled: Bool) {
        guard settings.displayNotificationsEnabled != enabled else { return }
        settings.displayNotificationsEnabled = enabled
        persistSettings()
        if enabled { NotificationDelivery.requestAuthorization() }
    }

    /// True when at least one external (non-built-in) display is currently present.
    var hasExternalDisplay: Bool { displays.contains { $0.displayClass != .builtIn } }

    /// On an external-arrival edge (and only then), turn the built-in panel off through the gated
    /// coordinator path (Issue 5). The built-in returns when the last external leaves — that's the
    /// existing always-one-active safety net (`enforceActiveSurfaceInvariant`), not duplicated here.
    @discardableResult
    private func applyAutoDisconnectBuiltInIfNeeded() async -> Bool {
        let fire = autoDisconnectPolicy.onTopologyChange(
            enabled: settings.autoDisconnectBuiltInOnExternal,
            externalPresent: hasExternalDisplay
        )
        guard fire, !busy,
              let builtIn = displays.first(where: { $0.displayClass == .builtIn && $0.isActive })
        else { return false }
        await setDisplayActive(false, for: builtIn)
        return true
    }

    /// Toggle for "auto-disconnect the built-in when an external connects" (Issue 5). Persists the
    /// setting; takes effect on the next external arrival (it never disconnects retroactively).
    func setAutoDisconnectBuiltInOnExternal(_ enabled: Bool) {
        guard settings.autoDisconnectBuiltInOnExternal != enabled else { return }
        settings.autoDisconnectBuiltInOnExternal = enabled
        persistSettings()
    }

    /// Toggle for "prevent display sleep while an external is connected" (Issue 3). Persists the
    /// setting and immediately reconciles the power assertion against the current topology.
    func setPreventDisplaySleepWithExternal(_ enabled: Bool) {
        guard settings.preventDisplaySleepWithExternal != enabled else { return }
        settings.preventDisplaySleepWithExternal = enabled
        persistSettings()
        reconcileDisplaySleepGuard()
    }

    /// Acquire or release the keep-awake assertion for the current (toggle, external-presence) state.
    /// Idempotent — safe to call on every topology change and every settings change.
    private func reconcileDisplaySleepGuard() {
        sleepGuard.update(
            enabled: settings.preventDisplaySleepWithExternal,
            externalPresent: hasExternalDisplay
        )
    }

    /// Persists `settings` to the on-disk store (best-effort; a write failure leaves the in-memory
    /// value authoritative for this session).
    private func persistSettings() {
        try? settingsStore?.save(settings)
    }

    /// The "one display is always active" safety net. If a topology change leaves nothing active —
    /// e.g. the last external is physically unplugged while the built-in is logically off — re-enable
    /// the built-in (or the most-recently disabled display) so the user is never left black-screened.
    private func enforceActiveSurfaceInvariant() async {
        guard !busy, displays.filter(\.isActive).isEmpty else { return }
        let fallback = managedOffline.first(where: { $0.displayClass == .builtIn }) ?? managedOffline.last
        guard let fallback else { return }
        #if DEBUG
        Self.err("ACTIVE-SURFACE GUARD: 0 active displays — re-enabling \(fallback.name)")
        #endif
        await reconnectOffline(fallback)
    }

    /// Emergency recovery — always available (PRD LIF-010). With live observation and no
    /// managed-offline displays yet, this is a safe no-op until a disconnect path is exercised.
    func reconnectAll() async {
        busy = true
        defer { busy = false }
        _ = await coordinator.reconnectAll()
        await refresh()
    }

    // MARK: - Quit-time revert

    /// True when the app has put the system into a non-default state whose reversal needs async work
    /// before the process exits — currently, a display it logically turned off. Gamma dim and the
    /// keep-awake assertion are restored synchronously by the `willTerminate` backstop, so they don't
    /// gate termination on their own.
    var needsQuitReversion: Bool {
        if !managedOffline.isEmpty { return true }
        #if !PUBLIC_API_ONLY
        // An applied evening colour preset owes the monitor its daytime preset back — quitting
        // must wait for that DDC write (the willTerminate backstop can't do async I2C).
        if !settings.adaptiveDayPresetByDisplay.isEmpty { return true }
        #endif
        return false
    }

    /// Reverts every app-made system change so quitting returns the Mac to a clean default: reconnect
    /// any display we turned off, lift any software dim/blackout, and drop keep-awake assertions. The
    /// delegate's `applicationShouldTerminate` defers termination until this completes so the
    /// reconnect actually lands before the process exits.
    func teardownForQuit() async {
        #if !PUBLIC_API_ONLY
        // Stop adaptive first, then hand back the monitor's daytime colour preset if the evening
        // one is applied — awaited directly (the coalesced writers are fire-and-forget; quitting
        // must not race them).
        adaptiveLoop?.cancel()
        adaptiveLoop = nil
        await restoreOwedDayPresets()
        #endif
        // Reconnect each off-card the way `reconnectOffline(_:)` does — by raw display id, since a
        // disabled display drops off the online list. `coordinator.reconnectAll()` only sees the
        // observer snapshot's offline list, which doesn't include this persisted `managedOffline`
        // set, so it would no-op here and leave the display off.
        for offline in managedOffline {
            let reconnectID = offline.cgID != 0
                ? DisplayRecordID(rawValue: "cgid:\(offline.cgID)")
                : offline.recordID
            try? await lifecycle.reconnect(reconnectID, deadline: Date().addingTimeInterval(10))
        }
        if !managedOffline.isEmpty {
            managedOffline.removeAll()
            persistManagedOffline()
        }
        CoreGraphicsProvider.restoreGamma()
        softwareDim.removeAll()
        sleepGuard.releaseAll()
    }

    // MARK: - Global keyboard shortcuts (Batch-2 #4)

    /// Registers a Carbon global hotkey for every bound action in the (defaults-merged) shortcut
    /// registry, mapping each to its handler. Reconnect-All honours the existing enable toggle.
    private func registerHotkeys() {
        hotKeys.removeAll()
        let registry = settings.hotkeyShortcuts.mergedWithDefaults()
        var nextID: UInt32 = 1
        for action in HotkeyAction.allCases {
            guard let binding = registry.binding(for: action) else { continue }
            if action == .reconnectAll && !settings.reconnectAllHotkeyEnabled { continue }
            if let hotkey = GlobalHotKey(keyCode: binding.keyCode, modifiers: binding.modifiers,
                                         id: nextID, action: hotkeyHandler(for: action)) {
                hotKeys.append(hotkey)
            }
            nextID += 1
        }
    }

    private func hotkeyHandler(for action: HotkeyAction) -> () -> Void {
        switch action {
        case .reconnectAll:
            return { [weak self] in
                #if DEBUG
                AppModel.debugMarkHotKeyFired()
                #endif
                Task { await self?.reconnectAll() }
            }
        case .cycleMainDisplay:
            return { [weak self] in Task { await self?.cycleMainDisplay() } }
        case .brightnessUp:
            return { [weak self] in Task { await self?.adjustMainBrightness(by: 0.1) } }
        case .brightnessDown:
            return { [weak self] in Task { await self?.adjustMainBrightness(by: -0.1) } }
        }
    }

    /// Makes the next active display the main display (wraps around).
    func cycleMainDisplay() async {
        let actives = displays.filter(\.isActive)
        guard actives.count > 1 else { return }
        let idx = actives.firstIndex(where: { $0.isMain }) ?? 0
        await setMain(for: actives[(idx + 1) % actives.count])
    }

    /// Nudges the main display's brightness by `delta`, clamped to 0...1.
    func adjustMainBrightness(by delta: Float) async {
        guard let main = displays.first(where: { $0.isMain }) else { return }
        let current = brightness[main.recordID] ?? 0.5
        setBrightness(max(0, min(1, current + delta)), for: main)
    }

    // MARK: - OSD HUD + media keys (Batch-3)

    /// Show the OSD HUD for a brightness/volume change and (when enabled) broadcast it for external/
    /// notch HUDs (Batch-3 #4/#6). The single funnel that `setBrightness` / `setHardwareControl(.volume)`
    /// call, so the HUD fires for every in-app source (menu slider, media keys).
    func presentOSD(kind: OSDContent.Kind, value: Float, for observation: DisplayObservation,
                    source: String = "app") {
        let content = OSDContent(kind: kind, value: value)
        if settings.osdEnabled && settings.osdStyle != .external {
            osdHUD.present(content, cgDisplayID: observation.cgDisplayID,
                           style: settings.osdStyle, position: settings.osdPosition)
        }
        if settings.publishOSDEventsEnabled {
            OSDBroadcaster.publish(kind: kind, value: Double(value),
                                   displayID: observation.recordID.rawValue,
                                   displayName: displayName(for: observation), source: source)
        }
    }

    /// Handle a captured media key (Batch-3 #1/#3). Resolves the target display via the pure
    /// `MediaKeyTargetPolicy`, applies the change through the existing brightness/volume sinks (which
    /// raise the OSD), and returns whether it acted — so the tap can swallow handled keys and let
    /// others (e.g. volume on the built-in) pass through to macOS.
    @discardableResult
    func handleMediaKey(_ action: MediaKeyAction, fineStep: Bool) -> Bool {
        // Volume/mute follow the system's default audio output (resolved at keypress); brightness
        // follows the configured target mode and ignores this.
        let audioTarget = action.isVolume ? audioOutputDisplayID() : nil
        guard let target = MediaKeyTargetPolicy.target(
            for: action, in: displays, cursor: cursorInCGCoordinates(),
            mode: settings.mediaKeyTargetMode, volumeCapable: volumeCapableDisplayIDs(),
            audioTarget: audioTarget)
        else { return false }
        let id = target.recordID

        switch action {
        case .brightnessUp, .brightnessDown:
            let current = brightness[id] ?? 0.5
            setBrightness(min(1, max(0, current + action.signedDelta(fineStep: fineStep))), for: target)
        case .volumeUp, .volumeDown:
            let current = ddcControl(.volume, for: target) ?? 0.5
            setHardwareControl(.volume, min(1, max(0, current + action.signedDelta(fineStep: fineStep))),
                               for: target)
        case .muteToggle:
            // A volume of 0 already renders the speaker-slash glyph; toggle to 0 or back to the prior level.
            let current = ddcControl(.volume, for: target) ?? 0
            if current > 0 {
                preMuteVolume[id] = current
                setHardwareControl(.volume, 0, for: target)
            } else {
                setHardwareControl(.volume, preMuteVolume[id] ?? 0.5, for: target)
            }
        }
        return true
    }

    /// External displays that can take DDC audio (VCP 0x62) — the only valid volume-key targets. The
    /// built-in is never included, so its volume keys pass through to system volume. Fail-open: an
    /// external whose capabilities haven't been read yet is treated as capable (`ddcSupports`).
    private func volumeCapableDisplayIDs() -> Set<DisplayRecordID> {
        Set(displays
            .filter { $0.displayClass != .builtIn && ddcSupports(HardwareControl.volume.vcp, for: $0) }
            .map(\.recordID))
    }

    /// The display the system's default audio output is routing through, or nil when the sound isn't
    /// going to a display (built-in speakers, AirPods, USB DAC, aggregate) or can't be matched to one.
    /// Reads CoreAudio at call time and resolves the device→display via the pure matcher, using the same
    /// user-facing names shown elsewhere. Volume keys pass through unless this returns a real display.
    private func audioOutputDisplayID() -> DisplayRecordID? {
        guard let output = AudioOutputInfo.currentDefaultOutput() else { return nil }
        let names = Dictionary(uniqueKeysWithValues: displays.map { ($0.recordID, displayName(for: $0)) })
        return AudioOutputDisplayMatcher.match(
            deviceName: output.name, transport: output.transport, displays: displays, names: names)
    }

    /// The pointer location in Core Graphics (top-left origin) coordinates, to match `observation.origin`
    /// (which comes from `CGDisplayBounds`). `NSEvent.mouseLocation` is bottom-left, so flip about the
    /// primary display's height.
    private func cursorInCGCoordinates() -> DisplayOrigin? {
        let mouse = NSEvent.mouseLocation
        guard let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main)?.frame.height else { return nil }
        return DisplayOrigin(x: Int(mouse.x.rounded()), y: Int((primaryHeight - mouse.y).rounded()))
    }

    /// Create/tear down the media-key tap to match the setting (Batch-3 #3). Idempotent.
    ///
    /// Owns the Accessibility flow end-to-end: when the feature is enabled but the grant is missing,
    /// it shows the system prompt (once per launch) and then polls until the grant appears, arming the
    /// tap the moment it does — the user grants in System Settings and the keys just start working,
    /// no relaunch. (The Debug build is adhoc-signed, so a rebuild can invalidate a previous grant;
    /// this same path recovers that case at next launch.)
    private func reconcileMediaKeyTap() {
        if settings.mediaKeyInterceptionEnabled {
            guard mediaKeyTap == nil else { return }
            let tap = MediaKeyTap { [weak self] action, fineStep in
                self?.handleMediaKey(action, fineStep: fineStep) ?? false
            }
            mediaKeyTap = tap
            if !tap.start() {
                if !promptedForAccessibility {
                    promptedForAccessibility = true
                    MediaKeyTap.promptForAccessibility()
                }
                armMediaKeyTapWhenTrusted(tap)
            }
        } else {
            mediaKeyTapRetry?.cancel()
            mediaKeyTapRetry = nil
            mediaKeyTap?.stop()
            mediaKeyTap = nil
        }
    }

    /// Polls for the Accessibility grant and arms `tap` when it lands. 2s cadence: TCC grants are a
    /// one-time manual act in System Settings, so the window between grant and pickup stays invisible.
    private func armMediaKeyTapWhenTrusted(_ tap: MediaKeyTap) {
        mediaKeyTapRetry?.cancel()
        mediaKeyTapRetry = Task { [weak self] in
            while !Task.isCancelled, !MediaKeyTap.isAccessibilityTrusted {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard !Task.isCancelled else { return }
            _ = tap.start()
            self?.mediaKeyTapRetry = nil
            self?.objectWillChange.send()  // Settings' "active" status row reads a computed var
        }
    }

    /// Whether the media-key tap is currently capturing keys (true only with the toggle on AND the
    /// Accessibility grant present). Drives the Settings status row.
    var mediaKeysActive: Bool { mediaKeyTap != nil && MediaKeyTap.isAccessibilityTrusted }

    /// Toggle media-key interception (Batch-3 #3). Persists; prompts for Accessibility when enabling
    /// without the grant; reconciles the tap.
    func setMediaKeyInterceptionEnabled(_ enabled: Bool) {
        guard settings.mediaKeyInterceptionEnabled != enabled else { return }
        settings.mediaKeyInterceptionEnabled = enabled
        persistSettings()
        reconcileMediaKeyTap()  // owns the Accessibility prompt + grant-poll when needed
    }

    func setMediaKeyTargetMode(_ mode: MediaKeyTargetMode) {
        guard settings.mediaKeyTargetMode != mode else { return }
        settings.mediaKeyTargetMode = mode
        persistSettings()
    }

    func setOSDEnabled(_ enabled: Bool) {
        guard settings.osdEnabled != enabled else { return }
        settings.osdEnabled = enabled
        persistSettings()
    }

    func setOSDStyle(_ style: OSDStyle) {
        guard settings.osdStyle != style else { return }
        settings.osdStyle = style
        persistSettings()
    }

    func setOSDPosition(_ position: OSDPosition) {
        guard settings.osdPosition != position else { return }
        settings.osdPosition = position
        persistSettings()
    }

    func setPublishOSDEventsEnabled(_ enabled: Bool) {
        guard settings.publishOSDEventsEnabled != enabled else { return }
        settings.publishOSDEventsEnabled = enabled
        persistSettings()
    }

    #if DEBUG
    /// Diagnostic dump of the observed topology to stderr, gated on `OPENDISPLAY_DUMP` so it is
    /// silent in normal runs. Run the app binary directly with the env var set to verify live
    /// enumeration without needing the menu-bar UI. DEBUG-only (excluded from release / App Store).
    private static func dump(_ snapshot: TopologySnapshot) {
        var out = "OpenDisplay topology \(snapshot.generation):\n"
        for o in snapshot.observations.sorted(by: { $0.recordID.rawValue < $1.recordID.rawValue }) {
            let mode = o.mode.map { "\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshHz.rounded()))" } ?? "—"
            out += "  \(o.isActive ? "●" : "○") \(o.recordID.rawValue)"
            out += " cgID=\(o.cgDisplayID ?? 0)\(o.isMain ? " [main]" : "")"
            out += " \(o.displayClass.rawValue) \(mode) origin=(\(o.origin.x),\(o.origin.y))"
            out += o.isMirrored ? " mirrors=\(o.mirrorSourceID?.rawValue ?? "")" : ""
            out += "\n"
        }
        FileHandle.standardError.write(Data(out.utf8))
    }

    /// M0 live-test harness (DEBUG only, gated on `OPENDISPLAY_DISCONNECT=<cgID|recordID>`): runs
    /// one real disconnect through the full coordinator transaction, logs the result + stage path
    /// to stderr, then **always reconnects after 3s** so a live test can never strand a display.
    /// Never target the main display — the coordinator blocks removing the last safe surface.
    private func debugDisconnectCycle(token: String) async {
        let snapshot = await observer.currentSnapshot()
        guard let observation = snapshot.observations.first(where: {
            $0.cgDisplayID.map(String.init) == token || $0.recordID.rawValue == token
        }) else {
            Self.err("DISCONNECT: no display matches \(token)")
            return
        }
        let target = observation.recordID
        // Reconnect by raw display ID so restore can't fail on UUID resolution after the display
        // drops off the online list while logically disabled.
        let reconnectID = observation.cgDisplayID.map { DisplayRecordID(rawValue: "cgid:\($0)") } ?? target

        Self.err("DISCONNECT target \(target.rawValue) (cgID \(observation.cgDisplayID ?? 0)) — running coordinator transaction…")
        do {
            let result = try await coordinator.disconnect(
                target, options: DisconnectOptions(actor: .cli, identityConfidence: 1.0)
            )
            let stages = await coordinator.lastTransition.map { "\($0)" }.joined(separator: " → ")
            Self.err("DISCONNECT result: \(result)\n  stages: \(stages)")
        } catch {
            Self.err("DISCONNECT error: \(error)")
        }
        // Proof of mechanism: with the private disable, the target drops out of the online list
        // (or is inactive with NO mirror source). The public mirror fallback would instead leave it
        // online with mirrorSourceID set. Captured during the offline window, before reconnect.
        let post = await observer.currentSnapshot()
        let summary = post.observations
            .map { "\($0.recordID.rawValue) active=\($0.isActive) mirror=\($0.mirrorSourceID?.rawValue ?? "none")" }
            .joined(separator: " | ")
        Self.err("POST-DISCONNECT online=\(post.observations.count): \(summary)")
        // Restore unconditionally so the test is self-healing. The hold is configurable (default
        // 3s) so a cross-process test can re-enable the display from another process meanwhile;
        // forAppOnly also reverts the disable if this process exits first.
        let holdSeconds = ProcessInfo.processInfo.environment["OPENDISPLAY_HOLD_SECONDS"]
            .flatMap(Double.init) ?? 3
        try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
        do {
            try await lifecycle.reconnect(reconnectID, deadline: Date().addingTimeInterval(10))
            Self.err("RECONNECT \(reconnectID.rawValue): done")
        } catch {
            Self.err("RECONNECT \(reconnectID.rawValue) error: \(error)")
        }
        await refresh()
    }

    private static func err(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Records a global-hotkey activation to stderr AND a fixed file, so a manual keypress test can
    /// be confirmed even when the app is launched via LaunchServices (which doesn't inherit stderr).
    private static func debugMarkHotKeyFired() {
        let message = Data("HOTKEY: Reconnect All triggered\n".utf8)
        FileHandle.standardError.write(message)
        let url = URL(fileURLWithPath: "/tmp/opendisplay_hotkey_fired.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(message)
            try? handle.close()
        } else {
            try? message.write(to: url)
        }
    }
    #endif
}

/// Prefers a primary lifecycle provider and falls back to a public one only when the primary
/// reports the operation `.unsupported` (e.g. the private SkyLight symbols are absent on this OS).
/// Other failures propagate — a real OS rejection must not silently retry by another mechanism.
private struct RoutedLifecycleProvider: LifecycleProvider {
    let primary: any LifecycleProvider
    let fallback: any LifecycleProvider

    let providerID = "routed.lifecycle.v1"
    var isExperimental: Bool { primary.isExperimental }

    func probe(_ environment: ProviderEnvironment) async -> ProviderProbe {
        let probe = await primary.probe(environment)
        return probe.status == .supported ? probe : await fallback.probe(environment)
    }

    func disconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try await active().disconnect(target, deadline: deadline)
    }

    func reconnect(_ target: DisplayRecordID, deadline: Date) async throws {
        try await active().reconnect(target, deadline: deadline)
    }

    func recover(to checkpoint: Checkpoint) async throws {
        try await active().recover(to: checkpoint)
    }

    /// Pick the provider by probe status — a forward capability check, so an unsupported primary
    /// never even attempts the operation. (`catch as ProviderFailure` is now also boundary-safe: the
    /// shared core ships as dynamic frameworks — see project.yml — so `ProviderFailure` has exactly
    /// one runtime type across all images. Error-based fallback would work too; probe-based routing is
    /// kept because deciding up front beats reacting to a thrown failure.)
    private func active() async -> any LifecycleProvider {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let environment = ProviderEnvironment(
            osBuild: "", isAppleSilicon: appleSilicon, transport: .unknown, displayClass: .unknown
        )
        return await primary.probe(environment).status == .supported ? primary : fallback
    }
}

/// Coarse menu-bar load state (a subset of the designed states: scanning → ready/empty).
enum DisplayLoadPhase: Equatable {
    case scanning
    case ready
    case empty
}

/// A provider status row shown in Settings → Diagnostics & Recovery.
struct DisplayDiagnostic: Identifiable, Hashable {
    var id: String { provider }
    var provider: String
    var status: String
    var risk: String
    var experimental: Bool
    var reasons: [String]
}
#endif
