#if os(macOS)
import AppKit
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import ProviderInterfaces
import SceneEngine
import TopologyCore
#if !PUBLIC_API_ONLY
import ExperimentalLifecycleProvider
#endif

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
    /// Displays the app has logically turned off. The OS drops them from the online list, so we track
    /// them here to keep an "off" card in the menu (with a way back on) and to feed the safety net.
    @Published private(set) var managedOffline: [OfflineDisplay] = []
    /// Cached brightness (0...1) for displays we can control — built-in via DisplayServices, externals
    /// via DDC. A missing key means "not controllable here", so the menu shows a disabled slider.
    @Published private(set) var brightness: [DisplayRecordID: Float] = [:]

    /// A display OpenDisplay turned off — remembered so it stays visible and re-enableable.
    struct OfflineDisplay: Identifiable, Equatable {
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
    #if !PUBLIC_API_ONLY
    private let brightnessControl = DisplayServicesBrightnessProvider()
    private var ddc: [DisplayRecordID: ExternalDisplayDDC] = [:]
    private var brightnessMax: [DisplayRecordID: Int] = [:]
    private var ddcTarget: [DisplayRecordID: Int] = [:]
    private var ddcWriters: [DisplayRecordID: Task<Void, Never>] = [:]
    #endif
    private var hotKey: GlobalHotKey?
    private var registry: DisplayRegistry?
    private var sceneLibrary: SceneLibrary?
    let settings: OpenDisplaySettings

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
        self.settings = AppModel.loadSettings()
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
            await refresh()
            await writeBaselineCheckpoint()
            #if DEBUG
            if let token = ProcessInfo.processInfo.environment["OPENDISPLAY_DISCONNECT"] {
                await debugDisconnectCycle(token: token)
            }
            #endif
        }
        Task { await observeTopologyChanges() }
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

    /// Loads persisted user settings, or defaults if the store can't be resolved/read.
    private static func loadSettings() -> OpenDisplaySettings {
        (try? SettingsStore.defaultDirectory()).map(SettingsStore.init(directory:))?.load() ?? .default
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
        diagnostics = [
            DisplayDiagnostic(provider: "Core Graphics (observation)", status: observation.status.rawValue,
                              risk: observation.risk.rawValue, experimental: observer.isExperimental,
                              reasons: observation.reasons.map(\.rawValue)),
            DisplayDiagnostic(provider: "Lifecycle (disconnect / reconnect)", status: lifecycleProbe.status.rawValue,
                              risk: lifecycleProbe.risk.rawValue, experimental: lifecycle.isExperimental,
                              reasons: lifecycleProbe.reasons.map(\.rawValue))
        ]
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
        var resolved: [DisplayRecordID: DisplayRecord] = [:]
        for observation in snapshot.observations {
            guard let cgID = observation.cgDisplayID else { continue }
            let fingerprint = observer.fingerprint(for: cgID)
            resolved[observation.recordID] = await registry.resolve(
                fingerprint: fingerprint, cgUUID: observation.cgUUID, displayClass: observation.displayClass
            )
        }
        records = resolved
    }

    private func setUpScenes() async {
        let store: any SceneStoring =
            (try? DiskSceneStore.defaultDirectory()).map { DiskSceneStore(directory: $0) }
            ?? InMemorySceneStore()
        let library = await SceneLibrary(store: store)
        sceneLibrary = library
        scenes = await library.all()
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

    /// Applies a saved scene's positions + modes to the current displays (user-triggered).
    func applyScene(_ scene: Scene) async {
        let snapshot = await observer.currentSnapshot()
        var targets: [CoreGraphicsProvider.ArrangementTarget] = []
        for member in scene.members {
            guard let observation = resolveSceneMember(member.selector, in: snapshot),
                  let cgID = observation.cgDisplayID else { continue }
            targets.append(.init(displayID: cgID, origin: member.desired.position, mode: member.desired.mode))
        }
        _ = observer.applyArrangement(targets)
        await refresh()
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
        // Drop any tracked off-display that has come back on its own (e.g. re-enabled elsewhere).
        managedOffline.removeAll { offline in
            displays.contains { $0.recordID == offline.recordID && $0.isActive }
        }
        statusText = "\(snapshot.activeDisplays.count) active · \(snapshot.observations.count) total"
        phase = displays.isEmpty ? .empty : .ready
        await resolveRecords(snapshot)
        await refreshDiagnostics()
        if ProcessInfo.processInfo.environment["OPENDISPLAY_DUMP"] != nil {
            Self.dump(snapshot)
            let names = displays.map { "cgID=\($0.cgDisplayID ?? 0) → \"\(displayName(for: $0))\"" }
                .joined(separator: ", ")
            FileHandle.standardError.write(Data("names: \(names)\n".utf8))
        }
    }

    // MARK: - Menu controls (Phase 1)

    /// Available resolutions for a display, de-duplicated per point-size — drives the resolution slider.
    func availableModes(for observation: DisplayObservation) -> [DisplayMode] {
        guard let cgID = observation.cgDisplayID else { return [] }
        return observer.availableModes(for: cgID)
    }

    /// Refreshes the cached brightness for a display — built-in via DisplayServices, external via DDC
    /// (async, since DDC round-trips over I2C). A display that can't be read is left out of the cache,
    /// so the UI shows a disabled "Soon" control. No-op in the public-API-only build.
    func refreshBrightness(for observation: DisplayObservation) async {
        #if !PUBLIC_API_ONLY
        guard let cgID = observation.cgDisplayID else { return }
        if observation.displayClass == .builtIn {
            if let value = brightnessControl.brightness(for: cgID) {
                brightness[observation.recordID] = value
            }
        } else if let controller = ddcController(for: observation),
                  let reading = await controller.read(.brightness), reading.max > 0 {
            brightness[observation.recordID] = Float(reading.current) / Float(reading.max)
            brightnessMax[observation.recordID] = reading.max
        }
        #endif
    }

    /// Sets a display's brightness (0...1), updating the cache optimistically. Built-in writes are
    /// immediate; external (DDC) writes are coalesced so a fast slider drag never floods the I2C bus —
    /// only the latest pending value is sent once the previous write completes.
    func setBrightness(_ value: Float, for observation: DisplayObservation) {
        #if !PUBLIC_API_ONLY
        guard let cgID = observation.cgDisplayID else { return }
        let id = observation.recordID
        brightness[id] = value
        if observation.displayClass == .builtIn {
            _ = brightnessControl.setBrightness(value, for: cgID)
        } else {
            ddcTarget[id] = Int((value * Float(brightnessMax[id] ?? 100)).rounded())
            if ddcWriters[id] == nil {
                ddcWriters[id] = Task { [weak self] in await self?.drainDDCWrites(id, observation) }
            }
        }
        #endif
    }

    #if !PUBLIC_API_ONLY
    private func ddcController(for observation: DisplayObservation) -> ExternalDisplayDDC? {
        if let existing = ddc[observation.recordID] { return existing }
        guard let cgID = observation.cgDisplayID,
              let controller = ExternalDisplayDDC(displayID: cgID) else { return nil }
        ddc[observation.recordID] = controller
        return controller
    }

    private func drainDDCWrites(_ id: DisplayRecordID, _ observation: DisplayObservation) async {
        guard let controller = ddcController(for: observation) else { ddcWriters[id] = nil; return }
        while let target = ddcTarget[id] {
            ddcTarget[id] = nil
            await controller.write(.brightness, target)
        }
        ddcWriters[id] = nil
    }
    #endif

    /// Applies a chosen resolution/mode, then re-reads the topology.
    func setMode(_ mode: DisplayMode, for observation: DisplayObservation) async {
        guard let cgID = observation.cgDisplayID else { return }
        _ = observer.applyArrangement([.init(displayID: cgID, origin: nil, mode: mode)])
        await refresh()
    }

    /// Makes a display the main display by re-anchoring every origin so this one sits at (0,0) —
    /// Core Graphics treats the display at the origin as main.
    func setMain(for observation: DisplayObservation) async {
        guard !observation.isMain else { return }
        let snapshot = await observer.currentSnapshot()
        let dx = -observation.origin.x
        let dy = -observation.origin.y
        let targets = snapshot.observations.compactMap { obs -> CoreGraphicsProvider.ArrangementTarget? in
            guard let cgID = obs.cgDisplayID else { return nil }
            return .init(displayID: cgID,
                         origin: DisplayOrigin(x: obs.origin.x + dx, y: obs.origin.y + dy),
                         mode: nil)
        }
        _ = observer.applyArrangement(targets)
        await refresh()
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
        await refresh()
    }

    /// Long-lived subscription to the observer's reconfiguration events: every hotplug, unplug,
    /// sleep, or enable/disable refreshes the UI and re-checks the always-one-active invariant.
    private func observeTopologyChanges() async {
        let stream = await observer.changes()
        for await _ in stream {
            await refresh()
            await enforceActiveSurfaceInvariant()
        }
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

    /// Diagnostic dump of the observed topology to stderr, gated on `OPENDISPLAY_DUMP` so it is
    /// silent in normal runs. Run the app binary directly with the env var set to verify live
    /// enumeration without needing the menu-bar UI.
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

    #if DEBUG
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
