import AutomationSchema
import CoreGraphicsProvider
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation
import ProviderInterfaces
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

typealias ResolvedDisplay = (observation: DisplayObservation, record: DisplayRecord)

/// Resolves every live display's fingerprint into the registry (recognizing or minting), so the
/// registry learns the current displays and we can map observations <-> records for this run.
func resolveCurrentDisplays() async -> [ResolvedDisplay] {
    let snapshot = await observer.currentSnapshot()
    var pairs: [ResolvedDisplay] = []
    for observation in snapshot.observations {
        guard let cgID = observation.cgDisplayID else { continue }
        let fingerprint = observer.fingerprint(for: cgID)
        let record = await registry.resolve(
            fingerprint: fingerprint, cgUUID: observation.cgUUID, displayClass: observation.displayClass
        )
        pairs.append((observation, record))
    }
    return pairs
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
            var displayClass: String; var mode: String?
        }
        emit(pairs.map {
            Row(id: $0.observation.recordID.rawValue, recordId: $0.record.id.rawValue, alias: $0.record.alias,
                tags: $0.record.tags.sorted(), cgDisplayID: $0.observation.cgDisplayID,
                active: $0.observation.isActive, main: $0.observation.isMain,
                displayClass: $0.observation.displayClass.rawValue, mode: modeString($0.observation))
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

// MARK: - Dispatch

switch command {
case "list": await runList()
case "diagnose": await runDiagnose()
case "alias": await runAlias()
case "tag": await runTag()
case "recover": await runRecover()
case "disconnect": await runDisconnect()
case "reconnect": await runReconnect()
case "help", "--help", "-h":
    print("""
    opendisplay — OpenDisplay automation CLI

    USAGE:
      opendisplay list [--json]
      opendisplay diagnose [--json]
      opendisplay alias <selector> <name>
      opendisplay tag <selector> <tag>
      opendisplay disconnect <selector> [--dry-run] [--json]
      opendisplay reconnect <selector> [--json]
      opendisplay recover [--json]

    SELECTORS: id:<recordID> · alias:<name> · tag:<tag> · main · builtin · state:<active|managedOffline> · <cgDisplayID>
    """)
default:
    fail("unknown command '\(command)' (try: list, diagnose, alias, tag, disconnect, reconnect, recover, help)", code: 2)
}
