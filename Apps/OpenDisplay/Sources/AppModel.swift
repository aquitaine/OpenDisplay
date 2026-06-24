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
    case contrast, volume

    var vcp: UInt8 {
        switch self {
        case .contrast: return 0x12
        case .volume: return 0x62
        }
    }
    var label: String {
        switch self {
        case .contrast: return "Contrast"
        case .volume: return "Volume"
        }
    }
    var icon: String {
        switch self {
        case .contrast: return "circle.lefthalf.filled"
        case .volume: return "speaker.wave.2"
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
    #endif
    private var hotKey: GlobalHotKey?
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
    /// Presents the floating "Keep these settings?" confirmation on the changed display (Issue 6).
    private let revertPresenter = RevertConfirmationPresenter()

    /// Edge detector for "auto-disconnect the built-in when an external connects" (Issue 5). Seeded to
    /// the launch topology so a pre-attached external isn't treated as a fresh arrival.
    private var autoDisconnectPolicy = AutoDisconnectBuiltInPolicy()

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
        // Always-available global Reconnect-All (recovery hierarchy step 3): reachable even when the
        // menu bar isn't. Skipped if disabled in settings; falls back to the menu-bar item if the
        // chord can't be registered.
        if settings.reconnectAllHotkeyEnabled {
            self.hotKey = GlobalHotKey.reconnectAll { [weak self] in
                #if DEBUG
                AppModel.debugMarkHotKeyFired()
                #endif
                Task { await self?.reconnectAll() }
            }
        }
        #if DEBUG
        let hotkeyState = settings.reconnectAllHotkeyEnabled
            ? (hotKey != nil ? "registered" : "FAILED")
            : "disabled in settings"
        FileHandle.standardError.write(Data("Global Reconnect-All hotkey (Ctrl-Opt-Cmd-R) \(hotkeyState)\n".utf8))
        #endif
        Task {
            await setUpRegistry()
            await setUpScenes()
            await loadManagedOffline()
            await refresh()
            await enforceActiveSurfaceInvariant()  // recover if we launched into a stranded (0-active) state
            reconcileDisplaySleepGuard()  // hold/release the keep-awake assertion for the launch topology
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
            MainActor.assumeIsolated { self?.sleepGuard.releaseAll() }
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
        await applyWithRevert(on ? "Mirroring turned on" : "Mirroring turned off", changedDisplayID: cgID) {
            _ = await self.observer.setMirroring(of: cgID, enabled: on)
        }
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
        } else if let controller = await ddcController(for: observation),
                  let reading = await controller.read(.brightness), reading.max > 0 {
            brightness[id] = Float(reading.current) / Float(reading.max)
            brightnessMax[id] = reading.max
            brightnessMethod[id] = .hardware
            return
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

    /// Reads every hardware (DDC) control for an external display into the cache. Skips the built-in
    /// and any feature the panel reports as unsupported. No-op in the public-API-only build.
    func refreshHardwareControls(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn, let controller = await ddcController(for: observation) else { return }
        let id = observation.recordID
        for control in HardwareControl.allCases {
            guard let feature = ExternalDisplayDDC.Feature(rawValue: control.vcp),
                  let reading = await controller.read(feature), reading.max > 0 else { continue }
            ddcControlLevel[id, default: [:]][control.vcp] = Float(reading.current) / Float(reading.max)
            ddcControlMax[DDCControlKey(id: id, vcp: control.vcp)] = reading.max
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
        #endif
    }

    #if !PUBLIC_API_ONLY
    private func drainHardwareWrites(_ key: DDCControlKey, _ control: HardwareControl, _ observation: DisplayObservation) async {
        guard let feature = ExternalDisplayDDC.Feature(rawValue: control.vcp),
              let controller = await ddcController(for: observation) else { ddcControlWriter[key] = nil; return }
        while let target = ddcControlTarget[key] {
            ddcControlTarget[key] = nil
            await controller.write(feature, target)
        }
        ddcControlWriter[key] = nil
    }
    #endif

    /// Reads the external display's current DDC input source into the cache.
    func refreshInputSource(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn, let controller = await ddcController(for: observation),
              let reading = await controller.read(.inputSource) else { return }
        inputSource[observation.recordID] = reading.current
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

    /// Reads the external display's current DDC colour preset (VCP 0x14) + its max code into the cache.
    func refreshColorPreset(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn, let controller = await ddcController(for: observation),
              let reading = await controller.read(.colorPreset) else { return }
        colorPreset[observation.recordID] = reading.current
        colorPresetMax[observation.recordID] = max(reading.max, 1)
        #endif
    }

    /// Sets the external display's DDC colour preset (sRGB / colour-temperature / native). User-driven.
    /// Coalesced per display (like input source) so rapid taps settle on the last choice in order.
    func setColorPreset(_ code: Int, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard observation.displayClass != .builtIn else { return }
        let id = observation.recordID
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
    #endif

    /// Applies a chosen resolution/mode behind the timed auto-revert gate (Issue 6), then re-reads the
    /// topology. A bad/blank resolution can leave a display unreadable, so the change is checkpointed
    /// and reverts itself unless confirmed within the window.
    func setMode(_ mode: DisplayMode, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        await applyWithRevert("Resolution changed on \(displayName(for: observation))", changedDisplayID: cgID) {
            _ = self.observer.applyArrangement([.init(displayID: cgID, origin: nil, mode: mode)])
        }
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
    func setMain(for observation: DisplayObservation) async {
        guard !observation.isMain else { return }
        await applyWithRevert("Main display changed to \(displayName(for: observation))",
                              changedDisplayID: observation.cgDisplayID) {
            let snapshot = await self.observer.currentSnapshot()
            let dx = -observation.origin.x
            let dy = -observation.origin.y
            let targets = snapshot.observations.compactMap { obs -> CoreGraphicsProvider.ArrangementTarget? in
                guard let cgID = obs.cgDisplayID else { return nil }
                return .init(displayID: cgID,
                             origin: DisplayOrigin(x: obs.origin.x + dx, y: obs.origin.y + dy),
                             mode: nil)
            }
            _ = self.observer.applyArrangement(targets)
        }
    }

    // MARK: - Timed auto-revert safety gate (Issue 6)

    /// Countdown length for an arrangement revert window. Reuses the existing confirmation-countdown
    /// setting (clamped to a sane minimum) so resolution/mirror/set-main share one tunable.
    private var arrangementRevertSeconds: Int { max(3, settings.arrangementAutoRevertSeconds) }

    /// Applies an arrangement-altering change (resolution / mirror / set-main) behind a macOS-style
    /// timed auto-revert: snapshot the prior arrangement, apply, then start a "Keep these settings?"
    /// countdown that restores the snapshot unless the user confirms. The auto-revert needs no user
    /// input, so recovery is guaranteed even if the changed display became unreadable; the prompt is
    /// surfaced on the menu-bar display (and the global Reconnect-All hotkey stays available too).
    private func applyWithRevert(
        _ message: String, changedDisplayID: CGDirectDisplayID?, _ apply: () async -> Void
    ) async {
        // A change made while a window is still open keeps the prior one, then opens a fresh window.
        if revertGate?.isPending == true { confirmArrangementChange() }
        let before = await observer.currentSnapshot().observations
        await apply()
        await refresh()
        beginRevertWindow(before: before, message: message, changedDisplayID: changedDisplayID)
    }

    private func beginRevertWindow(
        before: [DisplayObservation], message: String, changedDisplayID: CGDirectDisplayID?
    ) {
        let seconds = arrangementRevertSeconds
        revertGate = TimedRevertGate(before: before, deadline: Date().addingTimeInterval(Double(seconds)))
        revertMessage = message
        // Crash recovery: a marker (same Application Support dir the checkpoints/rotation marker use)
        // lets the next launch restore the prior arrangement if the app dies mid-window.
        Self.writeRevertMarker(before)
        pendingRevert = PendingRevert(message: message, secondsRemaining: seconds)
        // Surface the confirmation as a floating panel on the changed display (reliable regardless of
        // whether the change came from the menu or the Settings window).
        revertPresenter.show(model: self, changedDisplayID: changedDisplayID)
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
        revertPresenter.hide()
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
            await refresh()
            await enforceActiveSurfaceInvariant()
            reconcileDisplaySleepGuard()  // external arrived/left → acquire or release the keep-awake assertion
            await applyAutoDisconnectBuiltInIfNeeded()  // external just arrived → turn the built-in off (if enabled)
        }
    }

    /// True when at least one external (non-built-in) display is currently present.
    var hasExternalDisplay: Bool { displays.contains { $0.displayClass != .builtIn } }

    /// On an external-arrival edge (and only then), turn the built-in panel off through the gated
    /// coordinator path (Issue 5). The built-in returns when the last external leaves — that's the
    /// existing always-one-active safety net (`enforceActiveSurfaceInvariant`), not duplicated here.
    private func applyAutoDisconnectBuiltInIfNeeded() async {
        let fire = autoDisconnectPolicy.onTopologyChange(
            enabled: settings.autoDisconnectBuiltInOnExternal,
            externalPresent: hasExternalDisplay
        )
        guard fire, !busy,
              let builtIn = displays.first(where: { $0.displayClass == .builtIn && $0.isActive })
        else { return }
        await setDisplayActive(false, for: builtIn)
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
