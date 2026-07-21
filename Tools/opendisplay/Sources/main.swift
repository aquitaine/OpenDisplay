import AutomationSchema
import CoreGraphics
import CoreGraphicsProvider
import Dispatch
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation
import ProviderInterfaces
import SceneEngine
import TopologyCore

// OpenDisplay automation CLI (PRD §12). Mutating commands route through CommandGateway (the same
// audited, safety-checked path the UI and App Intents use). A persisted DisplayRegistry recognizes
// displays across reconnects and stores user aliases/tags, so `alias:`/`tag:` selectors resolve.
// `disconnect --dry-run` previews the SafetyEngine decision without touching hardware.

// MARK: - Argument parsing

let rawArgs = Array(CommandLine.arguments.dropFirst())
let flags = Set(rawArgs.filter { $0.hasPrefix("--") })
let positional = rawArgs.filter { !$0.hasPrefix("--") }
let command = positional.first ?? "list"
let selectorArg: String? = positional.count > 1 ? positional[1] : nil
let valueArg: String? = positional.count > 2 ? positional[2] : nil
let asJSON = flags.contains("--json")
let dryRun = flags.contains("--dry-run")

#if arch(arm64)
let isAppleSilicon = true
#else
let isAppleSilicon = false
#endif

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func emit<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
        fail("failed to encode JSON output")
    }
    print(text)
}

/// Encodes one `listen` event compactly (no pretty-printing) so it prints as exactly one line, with
/// sorted keys so two events with the same shape diff cleanly.
func emitLine<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
        fail("failed to encode JSON event")
    }
    print(text)
}

// MARK: - Composition root

let observer = CoreGraphicsProvider()
let environment = ProviderEnvironment(
    osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
    isAppleSilicon: isAppleSilicon, transport: .unknown, displayClass: .unknown
)
let experimental = ExperimentalLifecycleProvider()
let lifecycle: any LifecycleProvider =
    await experimental.probe(environment).status == .supported ? experimental : observer
let checkpoints: any CheckpointStoring =
    (try? DiskCheckpointStore.defaultDirectory()).map(DiskCheckpointStore.init(directory:))
    ?? InMemoryCheckpointStore()
let auditLog = (try? DiskAuditLog.defaultDirectory()).map(DiskAuditLog.init(directory:))
let gateway = CommandGateway(
    observer: observer, lifecycleProvider: lifecycle, checkpoints: checkpoints, auditLog: auditLog
)
let registryStore: any RegistryStoring =
    (try? DiskRegistryStore.defaultDirectory()).map { DiskRegistryStore(directory: $0) }
    ?? InMemoryRegistryStore()
let registry = await DisplayRegistry(store: registryStore)
let sceneStore: any SceneStoring =
    (try? DiskSceneStore.defaultDirectory()).map { DiskSceneStore(directory: $0) }
    ?? InMemorySceneStore()
let sceneLibrary = await SceneLibrary(store: sceneStore)

typealias ResolvedDisplay = (observation: DisplayObservation, record: DisplayRecord)

/// Resolves every live display's fingerprint into the registry (recognizing or minting), so the
/// registry learns the current displays and we can map observations <-> records for this run.
func resolveCurrentDisplays() async -> [ResolvedDisplay] {
    let snapshot = await observer.currentSnapshot()
    let observations = snapshot.observations.filter { $0.cgDisplayID != nil }
    let inputs = observations.compactMap {
        obs -> (fingerprint: DisplayFingerprint, cgUUID: String?, displayClass: DisplayClass)? in
        guard let cgID = obs.cgDisplayID else { return nil }
        return (observer.fingerprint(for: cgID), obs.cgUUID, obs.displayClass)
    }
    // One batched resolve → exactly one registry write for the whole display set this run.
    let records = await registry.resolveAll(inputs)
    return Array(zip(observations, records))
}

// MARK: - Selector resolution

func reachability(of observation: DisplayObservation, managedOffline: Set<DisplayRecordID>) -> Reachability {
    if managedOffline.contains(observation.recordID) { return .managedOffline }
    return observation.isActive ? .active : .discoveredInactive
}

func resolveObservation(_ raw: String, in pairs: [ResolvedDisplay],
                        managedOffline: Set<DisplayRecordID>) -> [DisplayObservation] {
    if let cgID = UInt32(raw) {
        return pairs.filter { $0.observation.cgDisplayID == cgID }.map(\.observation)
    }
    let selector: DisplaySelector
    do { selector = try DisplaySelector.parse(raw) } catch { fail("could not parse selector '\(raw)': \(error)") }
    switch selector {
    case .id(let recordID):
        return pairs.filter { $0.observation.recordID == recordID || $0.record.id == recordID }.map(\.observation)
    case .alias(let alias):
        return pairs.filter { $0.record.alias == alias }.map(\.observation)
    case .tag(let tag):
        return pairs.filter { $0.record.tags.contains(tag) }.map(\.observation)
    case .role(.main):
        return pairs.filter { $0.observation.isMain }.map(\.observation)
    case .role(.builtin):
        return pairs.filter { $0.observation.displayClass == .builtIn }.map(\.observation)
    case .state(let reach):
        return pairs.filter { reachability(of: $0.observation, managedOffline: managedOffline) == reach }.map(\.observation)
    case .role, .name, .fingerprint, .topology:
        fail("selector '\(raw)' isn't resolvable yet (use id:/alias:/tag:/main/builtin/state:/<cgID>)")
    }
}

func uniqueDisplay(_ raw: String, in pairs: [ResolvedDisplay],
                   managedOffline: Set<DisplayRecordID>) -> ResolvedDisplay {
    let matches = resolveObservation(raw, in: pairs, managedOffline: managedOffline)
    guard !matches.isEmpty else { fail("no display matches '\(raw)'") }
    guard matches.count == 1 else {
        fail("'\(raw)' is ambiguous (\(matches.count) displays): \(matches.map(\.recordID.rawValue).joined(separator: ", "))")
    }
    let observation = matches[0]
    return pairs.first { $0.observation.recordID == observation.recordID }!
}

// MARK: - Output

func name(for pair: ResolvedDisplay) -> String {
    pair.record.alias ?? pair.record.fingerprint.modelName ?? pair.observation.recordID.rawValue
}

func modeString(_ observation: DisplayObservation) -> String? {
    observation.mode.map { "\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshHz.rounded()))" }
}

func emitEnvelope(_ envelope: ResultEnvelope) {
    if asJSON { emit(envelope); return }
    print("\(envelope.status.rawValue) [\(envelope.transactionId)]")
    for target in envelope.targets {
        let ops = target.operations.map { "\($0.field)=\($0.verification.rawValue)" }.joined(separator: ", ")
        print("  \(target.displayId): \(ops)")
    }
    for error in envelope.errors {
        print("  ! \(error.code): \(error.message)")
    }
}

// MARK: - Commands

func runList() async {
    let pairs = await resolveCurrentDisplays().sorted { $0.observation.recordID.rawValue < $1.observation.recordID.rawValue }
    if asJSON {
        struct Row: Encodable {
            var id: String; var recordId: String; var alias: String?; var tags: [String]
            var cgDisplayID: UInt32?; var active: Bool; var main: Bool
            var displayClass: String; var mode: String?; var origin: String
        }
        emit(pairs.map {
            Row(id: $0.observation.recordID.rawValue, recordId: $0.record.id.rawValue, alias: $0.record.alias,
                tags: $0.record.tags.sorted(), cgDisplayID: $0.observation.cgDisplayID,
                active: $0.observation.isActive, main: $0.observation.isMain,
                displayClass: $0.observation.displayClass.rawValue, mode: modeString($0.observation),
                origin: "(\($0.observation.origin.x),\($0.observation.origin.y))")
        })
        return
    }
    for pair in pairs {
        let mark = pair.observation.isActive ? "●" : "○"
        let main = pair.observation.isMain ? " [main]" : ""
        let tags = pair.record.tags.isEmpty ? "" : " #\(pair.record.tags.sorted().joined(separator: " #"))"
        print("\(mark) \(name(for: pair))\(main) \(modeString(pair.observation) ?? "—")\(tags)")
    }
}

func runDiagnose() async {
    let probes = [
        ("coregraphics", false, await observer.probe(environment)),
        ("experimentalLifecycle", true, await experimental.probe(environment))
    ]
    if asJSON {
        struct Probe: Encodable { var provider: String; var experimental: Bool; var status: String; var risk: String; var reasons: [String] }
        emit(probes.map { id, experimental, probe in
            Probe(provider: id, experimental: experimental, status: probe.status.rawValue,
                  risk: probe.risk.rawValue, reasons: probe.reasons.map(\.rawValue))
        })
        return
    }
    for (id, experimental, probe) in probes {
        let labsTag = experimental ? " [labs]" : ""
        let reasons = probe.reasons.map(\.rawValue)
        let suffix = reasons.isEmpty ? "" : " (\(reasons.joined(separator: ",")))"
        print("\(id)\(labsTag): \(probe.status.rawValue) · risk=\(probe.risk.rawValue)\(suffix)")
    }
}

/// Prints the current ambient-light reading in lux — the direct ALS path Adaptive Display's ambient
/// mode falls back to (`Providers/ExperimentalLifecycleProvider/Sources/AmbientLight.swift`). Exits
/// non-zero when the sensor can't be read (no sensor, lid closed, or the IOKit SPI moved).
func runLux() async {
    guard let lux = AmbientLightReader().lux() else {
        fail("ambient light sensor unavailable (no sensor, lid closed, or SPI unreachable)")
    }
    if asJSON { emit(["lux": lux]) } else { print(String(format: "%.1f lux", lux)) }
}

/// Reports the lid's open/closed state via `LidStatePolicy`, reusing the same signals Adaptive
/// Display already senses. Exits non-zero only when this Mac has no built-in panel to reason about
/// at all (a desktop Mac) — see `LidStatePolicy` for why `closed` is otherwise inferred, not sensed.
func runLid() async {
    let snapshot = await observer.currentSnapshot()
    let builtInObservations = snapshot.observations.filter { $0.displayClass == .builtIn }
    let builtInIsActive = builtInObservations.contains { $0.isActive }
    let ambientLux = AmbientLightReader().lux()
    guard let state = LidStatePolicy.evaluate(
        builtInIsActive: builtInIsActive, hasBuiltInPanel: !builtInObservations.isEmpty,
        ambientLux: ambientLux
    ) else {
        fail("lid state unavailable — no built-in display observed on this Mac")
    }
    if asJSON { emit(["state": state.rawValue]) } else { print(state.rawValue) }
}

func runAlias() async {
    guard let selectorArg, let valueArg else { fail("usage: opendisplay alias <selector> <name>") }
    let pairs = await resolveCurrentDisplays()
    let snapshot = await observer.currentSnapshot()
    let target = uniqueDisplay(selectorArg, in: pairs, managedOffline: Set(snapshot.managedOffline.map(\.displayID)))
    await registry.setAlias(valueArg, for: target.record.id)
    print("aliased \(target.observation.recordID.rawValue) → \"\(valueArg)\"")
}

func runTag() async {
    guard let selectorArg, let valueArg else { fail("usage: opendisplay tag <selector> <tag>") }
    let pairs = await resolveCurrentDisplays()
    let snapshot = await observer.currentSnapshot()
    let target = uniqueDisplay(selectorArg, in: pairs, managedOffline: Set(snapshot.managedOffline.map(\.displayID)))
    await registry.addTag(valueArg, to: target.record.id)
    print("tagged \(name(for: target)) #\(valueArg)")
}

func runRecover() async {
    let envelope = await gateway.reconnectAll(actor: .cli)
    if !asJSON && envelope.targets.isEmpty {
        print("recover: nothing to reconnect")
        return
    }
    emitEnvelope(envelope)
}

func runDisconnect() async {
    guard let selectorArg else { fail("usage: opendisplay disconnect <selector> [--dry-run] [--json]") }
    let pairs = await resolveCurrentDisplays()
    let snapshot = await observer.currentSnapshot()
    let target = uniqueDisplay(selectorArg, in: pairs, managedOffline: Set(snapshot.managedOffline.map(\.displayID)))

    if dryRun {
        let outcome = await gateway.preflightDisconnect(target.observation.recordID, identityConfidence: 1.0)
        let surface = outcome.safeSurface?.rawValue ?? "none"
        switch outcome.decision {
        case .allowed:
            print("dry-run: ALLOWED — would disconnect \(name(for: target)); safe surface = \(surface)")
        case .needsConfirmation:
            print("dry-run: NEEDS CONFIRMATION (\(outcome.reasons.joined(separator: ","))) — safe surface = \(surface)")
        case .blocked:
            print("dry-run: BLOCKED (\(outcome.reasons.joined(separator: ",")))")
        }
        return
    }

    let envelope = await gateway.disconnect(
        target.observation.recordID, options: DisconnectOptions(actor: .cli, identityConfidence: 1.0)
    )
    emitEnvelope(envelope)
}

func runReconnect() async {
    guard let selectorArg else { fail("usage: opendisplay reconnect <selector> [--json]") }
    let pairs = await resolveCurrentDisplays()
    let snapshot = await observer.currentSnapshot()
    let target = uniqueDisplay(selectorArg, in: pairs, managedOffline: Set(snapshot.managedOffline.map(\.displayID)))
    do {
        try await lifecycle.reconnect(target.observation.recordID, deadline: Date().addingTimeInterval(15))
        if asJSON { emit(["status": "committed", "target": target.observation.recordID.rawValue]) }
        else { print("reconnected \(name(for: target))") }
    } catch {
        fail("reconnect failed: \(error)")
    }
}

// MARK: - Scenes

/// Resolves a scene member selector to a single record id, or nil if absent/ambiguous (unlike the
/// command selectors, a scene with an unresolved member is "missing", not an error).
func resolveMember(_ selector: String, in pairs: [ResolvedDisplay]) -> DisplayRecordID? {
    if let cgID = UInt32(selector) {
        let matches = pairs.filter { $0.observation.cgDisplayID == cgID }
        return matches.count == 1 ? matches[0].observation.recordID : nil
    }
    guard let parsed = try? DisplaySelector.parse(selector) else { return nil }
    let matches: [DisplayRecordID]
    switch parsed {
    case .id(let recordID):
        matches = pairs.filter { $0.observation.recordID == recordID || $0.record.id == recordID }.map(\.observation.recordID)
    case .alias(let alias):
        matches = pairs.filter { $0.record.alias == alias }.map(\.observation.recordID)
    case .tag(let tag):
        matches = pairs.filter { $0.record.tags.contains(tag) }.map(\.observation.recordID)
    case .role(.main):
        matches = pairs.filter { $0.observation.isMain }.map(\.observation.recordID)
    case .role(.builtin):
        matches = pairs.filter { $0.observation.displayClass == .builtIn }.map(\.observation.recordID)
    default:
        matches = []
    }
    return matches.count == 1 ? matches[0] : nil
}

func runScene() async {
    let sub = positional.count > 1 ? positional[1] : "list"
    let nameArg: String? = positional.count > 2 ? positional[2] : nil

    switch sub {
    case "list":
        let scenes = await sceneLibrary.all()
        if asJSON { emit(scenes) }
        else if scenes.isEmpty { print("no saved scenes (capture one with: scene save <name>)") }
        else { for scene in scenes { print("\(scene.name)  (\(scene.members.count) displays)") } }

    case "save":
        guard let nameArg else { fail("usage: opendisplay scene save <name>") }
        let snapshot = await observer.currentSnapshot()
        let id = await sceneLibrary.scene(named: nameArg)?.id ?? "scene_\(UUID().uuidString.prefix(8))"
        let scene = SceneRecorder.capture(from: snapshot, name: nameArg, id: String(id))
        await sceneLibrary.save(scene)
        print("saved scene \"\(nameArg)\" (\(scene.members.count) displays)")

    case "show":
        guard let nameArg, let scene = await sceneLibrary.scene(named: nameArg) else {
            fail("no scene named '\(nameArg ?? "")'")
        }
        if asJSON { emit(scene); return }
        print("Scene \"\(scene.name)\":")
        for member in scene.members {
            var parts: [String] = []
            if let connected = member.desired.connected { parts.append(connected ? "connected" : "offline") }
            if member.desired.main == true { parts.append("main") }
            if let p = member.desired.position { parts.append("pos=(\(p.x),\(p.y))") }
            if let m = member.desired.mode { parts.append("\(m.pixelWidth)x\(m.pixelHeight)") }
            print("  \(member.selector): \(parts.joined(separator: ", "))")
        }

    case "plan":
        guard let nameArg, let scene = await sceneLibrary.scene(named: nameArg) else {
            fail("no scene named '\(nameArg ?? "")'")
        }
        let pairs = await resolveCurrentDisplays()
        let snapshot = await observer.currentSnapshot()
        var resolution: ScenePlanner.Resolution = [:]
        for member in scene.members {
            if let recordID = resolveMember(member.selector, in: pairs) { resolution[member.selector] = recordID }
        }
        let plan = ScenePlanner().plan(scene: scene, snapshot: snapshot, resolution: resolution)
        if asJSON { emit(plan); return }
        if plan.isBlocked { print("scene \"\(scene.name)\": BLOCKED — missing required: \(plan.missingRequired.joined(separator: ", "))") }
        else if !plan.hasWork { print("scene \"\(scene.name)\": already satisfied (no changes)") }
        for op in plan.operations where op.status == .willApply {
            print("  → \(op.kind.rawValue) \(op.target.rawValue): \(op.detail)")
        }
        let satisfied = plan.operations.filter { $0.status == .alreadySatisfied }.count
        if satisfied > 0 { print("  (\(satisfied) already satisfied)") }
        for selector in plan.missingOptional { print("  · skipped (absent): \(selector)") }

    case "apply":
        guard let nameArg, let scene = await sceneLibrary.scene(named: nameArg) else {
            fail("no scene named '\(nameArg ?? "")'")
        }
        let pairs = await resolveCurrentDisplays()
        let snapshot = await observer.currentSnapshot()
        var targets: [CoreGraphicsProvider.ArrangementTarget] = []
        var skipped: [String] = []
        for member in scene.members {
            guard let recordID = resolveMember(member.selector, in: pairs),
                  let observation = snapshot.observation(for: recordID),
                  let cgID = observation.cgDisplayID else {
                skipped.append("\(member.selector): not present")
                continue
            }
            if let rotation = member.desired.rotation, rotation != .degrees0 {
                skipped.append("\(member.selector): rotation not applied (needs private API)")
            }
            if member.desired.brightness != nil { skipped.append("\(member.selector): brightness not applied (no control provider yet)") }
            if member.desired.connected == false { skipped.append("\(member.selector): disconnect not applied by scene apply") }
            targets.append(.init(displayID: cgID, origin: member.desired.position, mode: member.desired.mode))
        }
        guard !targets.isEmpty else { fail("scene \"\(scene.name)\" resolved to no present displays") }
        let warnings = observer.applyArrangement(targets)
        print("applied scene \"\(scene.name)\" to \(targets.count) display(s)")
        for note in warnings + skipped { print("  · \(note)") }

    case "delete":
        guard let nameArg, let scene = await sceneLibrary.scene(named: nameArg) else {
            fail("no scene named '\(nameArg ?? "")'")
        }
        await sceneLibrary.delete(id: scene.id)
        print("deleted scene \"\(nameArg)\"")

    default:
        fail("unknown scene subcommand '\(sub)' (try: list, save, show, plan, apply, delete)", code: 2)
    }
}

// MARK: - Control commands

/// Get or set a display's brightness (0..1). Built-in via DisplayServices, external via DDC.
func runBrightness() async {
    guard let sel = selectorArg else { fail("usage: opendisplay brightness <selector> [0..1]") }
    let pairs = await resolveCurrentDisplays()
    let target = uniqueDisplay(sel, in: pairs, managedOffline: [])
    guard let cgID = target.observation.cgDisplayID else { fail("display has no Core Graphics id") }
    let builtIn = target.observation.displayClass == .builtIn
    if let raw = valueArg {
        guard let level = Float(raw), (0...1).contains(level) else { fail("brightness value must be 0..1") }
        if builtIn {
            let ok = DisplayServicesBrightnessProvider().setBrightness(level, for: cgID)
            print(ok ? "\(name(for: target)): brightness = \(Int((level * 100).rounded()))%"
                     : "failed (DisplayServices unavailable)")
        } else if let ddc = ExternalDisplayDDC(displayID: cgID) {
            let maxValue = await ddc.read(.brightness)?.max ?? 100
            let ok = await ddc.write(.brightness, Int(level * Float(maxValue)))
            print(ok ? "\(name(for: target)): brightness = \(Int((level * 100).rounded()))% (DDC)"
                     : "DDC write failed")
        } else {
            fail("no brightness control for this display")
        }
    } else if builtIn, let value = DisplayServicesBrightnessProvider().brightness(for: cgID) {
        print("\(Int((value * 100).rounded()))%")
    } else if !builtIn, let ddc = ExternalDisplayDDC(displayID: cgID),
              let reading = await ddc.read(.brightness), reading.max > 0 {
        print("\(Int((Float(reading.current) / Float(reading.max) * 100).rounded()))% (\(reading.current)/\(reading.max), DDC)")
    } else {
        print("unsupported")
    }
}

/// Get or set a raw DDC/CI feature on an external display.
func runDDC() async {
    let featureNames: [String: ExternalDisplayDDC.Feature] = [
        "brightness": .brightness, "contrast": .contrast, "volume": .volume, "input": .inputSource,
        "colour": .colorPreset, "color": .colorPreset, "preset": .colorPreset,
        "sharpness": .sharpness, "red": .redGain, "green": .greenGain, "blue": .blueGain,
        "mute": .audioMute,
    ]
    let usage = "usage: opendisplay ddc <selector> <brightness|contrast|volume|input|colour|sharpness|red|green|blue|mute|power|caps|vcp <0xNN>> [value]"
    guard let sel = selectorArg, let featureArg = valueArg else { fail(usage) }
    let featureKey = featureArg.lowercased()
    let isCaps = featureKey == "caps" || featureKey == "capabilities"
    guard isCaps || featureKey == "power" || featureKey == "vcp" || featureNames[featureKey] != nil else {
        fail("unknown feature '\(featureArg)' — \(usage)")
    }
    let pairs = await resolveCurrentDisplays()
    let target = uniqueDisplay(sel, in: pairs, managedOffline: [])
    guard let cgID = target.observation.cgDisplayID, let ddc = ExternalDisplayDDC(displayID: cgID) else {
        fail("no DDC for this display (external displays only)")
    }
    // Capabilities (VCP 0xF3): read the display's advertised feature set, read-only.
    if isCaps {
        if let raw = await ddc.readCapabilitiesString() {
            print("capabilities: \(raw)")
            if let caps = DDCCapabilities.parse(raw) {
                let codes = caps.supportedVCPCodes.sorted().map { String(format: "0x%02X", $0) }.joined(separator: " ")
                print("supported VCP codes: \(codes)")
            }
        } else {
            print("capabilities: unavailable")
        }
        return
    }
    let setValue = positional.count > 3 ? positional[3] : nil
    // Raw VCP escape hatch: monitors implement far more of MCCS than we name (KVM switches, OSD
    // language, colour temperature, power LEDs…). `ddc <sel> vcp 0x87 [value]` reads/writes ANY
    // code — 0x-prefixed hex or plain decimal — so a new panel's controls are reachable without a
    // rebuild. Same best-effort semantics as the named features.
    if featureKey == "vcp" {
        guard let codeArg = setValue else { fail("usage: opendisplay ddc <selector> vcp <0xNN|decimal> [value]") }
        let lower = codeArg.lowercased()
        let code: UInt8? = lower.hasPrefix("0x") ? UInt8(lower.dropFirst(2), radix: 16) : UInt8(lower)
        guard let code else { fail("bad VCP code '\(codeArg)' (0x00–0xFF, e.g. 0x87)") }
        let label = String(format: "vcp 0x%02X", code)
        if positional.count > 4 {
            // DDC values are 16-bit on the wire; an unchecked Int would be silently truncated and
            // the success message would then lie about what was written.
            guard let value = Int(positional[4]), (0...0xFFFF).contains(value) else {
                fail("value must be an integer 0-65535")
            }
            let ok = await ddc.write(vcp: code, value)
            print(ok ? "\(label) = \(value)" : "DDC write failed")
        } else if let reading = await ddc.read(vcp: code) {
            print("\(label): \(reading.current)/\(reading.max)")
        } else {
            print("\(label): unsupported")
        }
        return
    }
    // Power is a one-shot DPM command whose value is a word (on|standby|off), not a numeric level.
    // Best-effort: a NAK/ignore just reports a failed write, never crashes.
    if featureKey == "power" {
        guard let raw = setValue else {
            fail("usage: opendisplay ddc <selector> power <\(DDCPowerMode.acceptedTokens)>")
        }
        guard let mode = DDCPowerMode(parsing: raw) else {
            fail("unknown power mode '\(raw)' (\(DDCPowerMode.acceptedTokens))")
        }
        let ok = await ddc.write(.power, mode.vcpValue)
        print(ok ? "power = \(mode.label)" : "DDC write failed")
        return
    }
    guard let feature = featureNames[featureKey] else {
        fail("unknown feature '\(featureArg)' — \(usage)")
    }
    if var raw = setValue {
        // VCP 0x8D (mute) is discrete — 1 = mute, 2 = unmute — which nobody guesses from numbers;
        // accept the words. (`power` gets the same treatment via DDCPowerMode above.)
        if feature == .audioMute {
            switch raw.lowercased() {
            case "on", "mute", "muted": raw = "1"
            case "off", "unmute", "unmuted": raw = "2"
            default: break
            }
        }
        guard let value = Int(raw), (0...0xFFFF).contains(value) else {
            fail(feature == .audioMute ? "mute value must be on|off (or 1=mute, 2=unmute)"
                                       : "value must be an integer 0-65535")
        }
        let ok = await ddc.write(feature, value)
        print(ok ? "\(featureArg) = \(value)" : "DDC write failed")
    } else if let reading = await ddc.read(feature) {
        print("\(featureArg): \(reading.current)/\(reading.max)")
    } else {
        print("\(featureArg): unsupported")
    }
}

func runEDID() async {
    guard let sel = selectorArg else { fail("usage: opendisplay edid <selector> [--out <path.bin>]") }
    let pairs = await resolveCurrentDisplays()
    let target = uniqueDisplay(sel, in: pairs, managedOffline: [])
    guard let cgID = target.observation.cgDisplayID else { fail("no display for selector '\(sel)'") }
    guard let bytes = EDIDReader.rawEDID(for: cgID) else {
        print("edid: unavailable for this display")
        return
    }
    if let edid = EDID.parse(bytes) {
        print("manufacturer:     \(edid.manufacturerID)")
        print("product code:     \(edid.productCode)")
        if let n = edid.monitorName { print("model:            \(n)") }
        if let s = edid.serialText { print("serial (text):    \(s)") }
        if edid.serialNumber != 0 { print("serial (numeric): \(edid.serialNumber)") }
        print("edid version:     \(edid.edidVersion).\(edid.edidRevision)")
        if let y = edid.manufactureYear {
            print("manufactured:     week \(edid.manufactureWeek.map(String.init) ?? "?") / \(y)")
        }
        if let r = edid.preferredResolution { print("preferred:        \(r.width)x\(r.height)") }
        if let w = edid.widthCm, let h = edid.heightCm { print("size:             \(w)x\(h) cm") }
        print("checksum:         \(edid.checksumValid ? "valid" : "INVALID")")
        print("extensions:       \(edid.extensionCount)")
        print("hash:             \(EDID.stableHash(bytes))")
    } else {
        print("edid: \(bytes.count) bytes read, but the base block failed to parse")
    }
    if let i = rawArgs.firstIndex(of: "--out"), i + 1 < rawArgs.count {
        let path = rawArgs[i + 1]
        do {
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            print("wrote \(bytes.count) bytes → \(path)")
        } catch {
            print("write failed: \(error)")
        }
    }
}

/// Parses a mode argument like `1920x1080`, `1920x1080@60`, or `1512x982@60@2x` into a `DisplayMode`
/// (pixel size mirrors point size; only point-size/refresh/HiDPI matter for the favourite key).
func parseModeArg(_ s: String) -> DisplayMode? {
    let hiDPI = s.contains("@2x")
    let parts = s.replacingOccurrences(of: "@2x", with: "").split(separator: "@")
    let dims = parts[0].lowercased().split(separator: "x")
    guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) else { return nil }
    let hz = parts.count > 1 ? (Double(parts[1]) ?? 60) : 60
    return DisplayMode(pixelWidth: w, pixelHeight: h, pointWidth: w, pointHeight: h, refreshHz: hz, isHiDPI: hiDPI)
}

func runFavorite() async {
    guard let sub = selectorArg, let sel = valueArg else {
        fail("usage: opendisplay favorite <list|set|unset> <selector> [WxH[@Hz][@2x]]")
    }
    let store = (try? SettingsStore.defaultDirectory()).map(FavoritesStore.init(directory:))
    var favorites = store?.load() ?? FavoriteResolutions()
    let pairs = await resolveCurrentDisplays()
    let target = uniqueDisplay(sel, in: pairs, managedOffline: [])
    let recordID = target.record.id
    switch sub.lowercased() {
    case "list":
        let keys = favorites.favoriteKeys(for: recordID)
        print(keys.isEmpty ? "(no favourites)" : keys.joined(separator: "\n"))
    case "set", "unset":
        guard positional.count > 3, let mode = parseModeArg(positional[3]) else {
            fail("mode must look like 1920x1080[@60][@2x]")
        }
        if sub.lowercased() == "set" { favorites.add(mode, for: recordID) }
        else { favorites.remove(mode, for: recordID) }
        try? store?.save(favorites)
        print("\(sub.lowercased()) \(FavoriteResolutions.key(for: mode)) for \(name(for: target))")
    default:
        fail("unknown favorite subcommand '\(sub)' (list|set|unset)")
    }
}

// MARK: - Experimental rotation helper (short-lived, gated, isolated)

/// EXPERIMENTAL rotation writer. Gated behind OPENDISPLAY_EXPERIMENTAL_ROTATION=1 so it never runs by
/// accident. Validates the angle + display safety, calls the private SkyLight rotator, polls
/// CGDisplayRotation to confirm, verifies no other display moved, and rolls back on any mismatch.
/// Running this in its own process isolates the app from a client-side WindowServer crash.
func runRotateExperimental() async {
    guard ProcessInfo.processInfo.environment["OPENDISPLAY_EXPERIMENTAL_ROTATION"] == "1" else {
        fail("experimental rotation disabled — set OPENDISPLAY_EXPERIMENTAL_ROTATION=1 to opt in", code: 3)
    }
    guard let sel = selectorArg, let raw = valueArg, let degrees = Int(raw) else {
        fail("usage: OPENDISPLAY_EXPERIMENTAL_ROTATION=1 opendisplay _rotate-exp <selector> <0|90|180|270>")
    }
    guard [0, 90, 180, 270].contains(degrees) else { fail("angle must be 0, 90, 180 or 270") }
    let pairs = await resolveCurrentDisplays()
    let target = uniqueDisplay(sel, in: pairs, managedOffline: [])
    guard let cgID = target.observation.cgDisplayID else { fail("target has no Core Graphics id") }
    let snapshot = await observer.currentSnapshot()
    let active = snapshot.activeDisplays
    guard target.observation.isActive else { fail("target display is not active") }
    guard target.observation.mirrorSourceID == nil else { fail("refusing to rotate a mirrored display") }
    guard active.count > 1 else { fail("refusing: target is the only active display") }

    let before = Int(CGDisplayRotation(cgID).rounded())
    let rotator = SkyLightDisplayRotator()
    guard rotator.isAvailable else { fail("SLSSetDisplayRotation unavailable on this OS", code: 4) }

    let rc = rotator.rotate(Int32(degrees), displayID: cgID)
    var observed = before
    for _ in 0..<12 { usleep(150_000); observed = Int(CGDisplayRotation(cgID).rounded()); if observed == degrees { break } }
    // No other active display should have changed rotation.
    let othersOK = active.allSatisfy { other in
        guard let oid = other.cgDisplayID, oid != cgID else { return true }
        return Int(CGDisplayRotation(oid).rounded()) == other.rotation.rawValue
    }
    if observed == degrees && othersOK {
        print("rotated \(cgID) \(before)° → \(degrees)° (rc=\(rc))")
    } else {
        _ = rotator.rotate(Int32(before), displayID: cgID)
        fail("verification failed (rc=\(rc), observed=\(observed)°, othersOK=\(othersOK)) — rolled back to \(before)°", code: 5)
    }
}

// MARK: - Listen (line-delimited JSON event stream)

/// Keeps the Ctrl-C signal source alive for the process's lifetime — a `DispatchSourceSignal` stops
/// firing the moment nothing retains it, so a local `let` inside `installCleanSigintExit` would be
/// silently deallocated before any signal ever arrived. `nonisolated(unsafe)`: written once at
/// startup, on the same thread that later reads it only to keep it retained (matches the retained-
/// token pattern in `GlobalHotKey.swift`).
nonisolated(unsafe) var sigintSource: DispatchSourceSignal?

/// Installs a clean Ctrl-C exit for `listen`: ignore the default disposition (which would kill the
/// process mid-write) and `exit(0)` from a dedicated queue once the signal lands.
func installCleanSigintExit() {
    signal(SIGINT, SIG_IGN)
    let queue = DispatchQueue(label: "opendisplay.listen.sigint")
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
    source.setEventHandler { exit(0) }
    source.resume()
    sigintSource = source
}

/// The live topology as `listen`'s compact per-display summary.
func summarizeCurrentDisplays() async -> [ListenEvent.DisplaySummary] {
    let snapshot = await observer.currentSnapshot()
    return snapshot.observations.map {
        ListenEvent.DisplaySummary(id: $0.recordID.rawValue, active: $0.isActive, main: $0.isMain,
                                   mode: modeString($0))
    }
}

/// Streams a `config` event on every topology change (hotplug, mode, rotation, mirror, main display).
func watchConfigEvents() async {
    let topologyChanges = await observer.changes()
    for await _ in topologyChanges {
        let displays = await summarizeCurrentDisplays()
        emitLine(ListenEvent.config(at: Date().timeIntervalSince1970, displays: displays))
    }
}

/// Streams a `brightness` event for every live `OSDBroadcast` (menu/media-key/CLI/App-Intent origin).
/// Requires "Broadcast OSD events" enabled in OpenDisplay's settings — `runListen` warns on stderr
/// once at startup when it's off.
func watchBrightnessEvents() async {
    let center = DistributedNotificationCenter.default()
    let broadcastName = Notification.Name(OSDBroadcast.notificationName)
    for await notification in center.notifications(named: broadcastName) {
        guard let userInfo = notification.userInfo as? [String: String],
              let broadcast = OSDBroadcast(userInfo: userInfo), broadcast.kind == .brightness
        else { continue }
        emitLine(ListenEvent.brightness(from: broadcast))
    }
}

/// One-time stderr note when the app hasn't opted into broadcasting brightness changes — otherwise
/// `listen` would sit silent on brightness with no clue why.
func warnIfBrightnessEventsAreOff() {
    let settingsStore = (try? SettingsStore.defaultDirectory()).map(SettingsStore.init(directory:))
    guard settingsStore?.load().publishOSDEventsEnabled != true else { return }
    FileHandle.standardError.write(Data(
        "note: brightness events need \"Broadcast OSD events\" on in OpenDisplay settings\n".utf8))
}

/// Streams brightness + config-change events as line-delimited JSON until Ctrl-C. Line-buffered
/// (`setvbuf`) so a piped consumer (`| jq`, `| tail -f`) sees each event as it happens rather than
/// batched at exit.
func runListen() async {
    setvbuf(stdout, nil, _IOLBF, 0)
    installCleanSigintExit()
    warnIfBrightnessEventsAreOff()
    async let brightnessEvents: Void = watchBrightnessEvents()
    async let configEvents: Void = watchConfigEvents()
    _ = await (brightnessEvents, configEvents)
}

// MARK: - Dispatch

switch command {
case "list": await runList()
case "diagnose": await runDiagnose()
case "lux": await runLux()
case "lid": await runLid()
case "listen": await runListen()
case "alias": await runAlias()
case "tag": await runTag()
case "recover": await runRecover()
case "disconnect": await runDisconnect()
case "reconnect": await runReconnect()
case "scene": await runScene()
case "brightness": await runBrightness()
case "ddc": await runDDC()
case "edid": await runEDID()
case "favorite", "favourite": await runFavorite()
case "_rotate-exp": await runRotateExperimental()
case "help", "--help", "-h":
    print("""
    opendisplay — OpenDisplay automation CLI

    USAGE:
      opendisplay list [--json]
      opendisplay diagnose [--json]
      opendisplay lux [--json]
      opendisplay lid [--json]
      opendisplay listen
      opendisplay alias <selector> <name>
      opendisplay tag <selector> <tag>
      opendisplay disconnect <selector> [--dry-run] [--json]
      opendisplay reconnect <selector> [--json]
      opendisplay recover [--json]
      opendisplay scene <list|save|show|plan|apply|delete> [name] [--json]
      opendisplay brightness <selector> [0..1]
      opendisplay ddc <selector> <brightness|contrast|volume|input|colour|sharpness|red|green|blue|mute|power|caps> [value]
      opendisplay ddc <selector> vcp <0xNN> [value]   # any raw MCCS feature code
      opendisplay edid <selector> [--out <path.bin>]
      opendisplay favorite <list|set|unset> <selector> [WxH[@Hz][@2x]]

    lux/lid exit non-zero when the sensor/state is unavailable. listen streams line-delimited JSON
    (one event per line) until Ctrl-C; see Tools/opendisplay/README.md for the event schema.

    SELECTORS: id:<recordID> · alias:<name> · tag:<tag> · main · builtin · state:<active|managedOffline> · <cgDisplayID>
    """)
default:
    fail("unknown command '\(command)' (try: list, diagnose, lux, lid, listen, alias, tag, disconnect, reconnect, recover, scene, brightness, ddc, help)", code: 2)
}
