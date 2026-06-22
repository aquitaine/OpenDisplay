import AutomationSchema
import CoreGraphicsProvider
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation
import ProviderInterfaces
import TopologyCore

// OpenDisplay automation CLI (PRD §12). Every mutating command routes through CommandGateway — the
// same audited, safety-checked path the menu bar and App Intents use — and returns the stable JSON
// ResultEnvelope. `disconnect --dry-run` previews the SafetyEngine decision without touching
// hardware. Selector grammar per DisplaySelector (PRD §12.3).

// MARK: - Argument parsing

let rawArgs = Array(CommandLine.arguments.dropFirst())
let flags = Set(rawArgs.filter { $0.hasPrefix("--") })
let positional = rawArgs.filter { !$0.hasPrefix("--") }
let command = positional.first ?? "list"
let selectorArg: String? = positional.count > 1 ? positional[1] : nil
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

// MARK: - Composition root (real providers, shared on-disk checkpoints + audit, one gateway)

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

// MARK: - Selector resolution (against live observations)

func reachability(of observation: DisplayObservation, managedOffline: Set<DisplayRecordID>) -> Reachability {
    if managedOffline.contains(observation.recordID) { return .managedOffline }
    return observation.isActive ? .active : .discoveredInactive
}

func resolve(_ raw: String, in snapshot: TopologySnapshot) throws -> [DisplayObservation] {
    if let cgID = UInt32(raw) {
        return snapshot.observations.filter { $0.cgDisplayID == cgID }
    }
    let selector = try DisplaySelector.parse(raw)
    let offline = Set(snapshot.managedOffline.map(\.displayID))
    switch selector {
    case .id(let recordID):
        return snapshot.observations.filter { $0.recordID == recordID }
    case .role(.main):
        return snapshot.observations.filter(\.isMain)
    case .role(.builtin):
        return snapshot.observations.filter { $0.displayClass == .builtIn }
    case .state(let reach):
        return snapshot.observations.filter { reachability(of: $0, managedOffline: offline) == reach }
    case .role, .alias, .tag, .name, .fingerprint, .topology:
        fail("selector '\(raw)' isn't resolvable yet from live observations (use id:/main/builtin/state:/<cgID>)")
    }
}

func uniqueTarget(_ raw: String, in snapshot: TopologySnapshot) -> DisplayObservation {
    let matches: [DisplayObservation]
    do {
        matches = try resolve(raw, in: snapshot)
    } catch {
        fail("could not parse selector '\(raw)': \(error)")
    }
    guard !matches.isEmpty else { fail("no display matches '\(raw)'") }
    guard matches.count == 1 else {
        fail("'\(raw)' is ambiguous (\(matches.count) displays): \(matches.map(\.recordID.rawValue).joined(separator: ", "))")
    }
    return matches[0]
}

// MARK: - Output

struct ListOutput: Encodable {
    struct Display: Encodable {
        var id: String
        var cgDisplayID: UInt32?
        var active: Bool
        var main: Bool
        var displayClass: String
        var transport: String
        var mode: String?
        var origin: String
    }
    var topologyGeneration: UInt64
    var displays: [Display]
}

struct DiagnoseOutput: Encodable {
    struct Probe: Encodable {
        var provider: String
        var experimental: Bool
        var status: String
        var risk: String
        var reasons: [String]
    }
    var providers: [Probe]
}

func modeString(_ observation: DisplayObservation) -> String? {
    observation.mode.map { "\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshHz.rounded()))" }
}

/// Prints a ResultEnvelope as JSON (--json) or a compact human summary.
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
    let snapshot = await observer.currentSnapshot()
    let sorted = snapshot.observations.sorted { $0.recordID.rawValue < $1.recordID.rawValue }
    if asJSON {
        emit(ListOutput(
            topologyGeneration: snapshot.generation.value,
            displays: sorted.map {
                .init(id: $0.recordID.rawValue, cgDisplayID: $0.cgDisplayID, active: $0.isActive,
                      main: $0.isMain, displayClass: $0.displayClass.rawValue,
                      transport: $0.transport.rawValue, mode: modeString($0),
                      origin: "(\($0.origin.x),\($0.origin.y))")
            }
        ))
        return
    }
    for observation in sorted {
        let mark = observation.isActive ? "●" : "○"
        let main = observation.isMain ? " [main]" : ""
        let mode = modeString(observation) ?? "—"
        print("\(mark) \(observation.recordID.rawValue)\(main) \(observation.displayClass.rawValue) \(mode)")
    }
}

func runDiagnose() async {
    let probes = [
        ("coregraphics", false, await observer.probe(environment)),
        ("experimentalLifecycle", true, await experimental.probe(environment))
    ]
    if asJSON {
        emit(DiagnoseOutput(providers: probes.map { id, experimental, probe in
            .init(provider: id, experimental: experimental, status: probe.status.rawValue,
                  risk: probe.risk.rawValue, reasons: probe.reasons.map(\.rawValue))
        }))
        return
    }
    for (id, experimental, probe) in probes {
        let labsTag = experimental ? " [labs]" : ""
        let reasons = probe.reasons.map(\.rawValue)
        let reasonsSuffix = reasons.isEmpty ? "" : " (\(reasons.joined(separator: ",")))"
        print("\(id)\(labsTag): \(probe.status.rawValue) · risk=\(probe.risk.rawValue)\(reasonsSuffix)")
    }
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
    let snapshot = await observer.currentSnapshot()
    let target = uniqueTarget(selectorArg, in: snapshot)

    if dryRun {
        let outcome = await gateway.preflightDisconnect(target.recordID, identityConfidence: 1.0)
        let surface = outcome.safeSurface?.rawValue ?? "none"
        switch outcome.decision {
        case .allowed:
            print("dry-run: ALLOWED — would disconnect \(target.recordID.rawValue); safe surface = \(surface)")
        case .needsConfirmation:
            print("dry-run: NEEDS CONFIRMATION (\(outcome.reasons.joined(separator: ","))) — safe surface = \(surface)")
        case .blocked:
            print("dry-run: BLOCKED (\(outcome.reasons.joined(separator: ",")))")
        }
        return
    }

    let envelope = await gateway.disconnect(
        target.recordID, options: DisconnectOptions(actor: .cli, identityConfidence: 1.0)
    )
    emitEnvelope(envelope)
}

func runReconnect() async {
    guard let selectorArg else { fail("usage: opendisplay reconnect <selector> [--json]") }
    let snapshot = await observer.currentSnapshot()
    let target = uniqueTarget(selectorArg, in: snapshot)
    do {
        try await lifecycle.reconnect(target.recordID, deadline: Date().addingTimeInterval(15))
        if asJSON {
            emit(["status": "committed", "target": target.recordID.rawValue])
        } else {
            print("reconnected \(target.recordID.rawValue)")
        }
    } catch {
        fail("reconnect failed: \(error)")
    }
}

// MARK: - Dispatch

switch command {
case "list": await runList()
case "diagnose": await runDiagnose()
case "recover": await runRecover()
case "disconnect": await runDisconnect()
case "reconnect": await runReconnect()
case "help", "--help", "-h":
    print("""
    opendisplay — OpenDisplay automation CLI

    USAGE:
      opendisplay list [--json]
      opendisplay diagnose [--json]
      opendisplay disconnect <selector> [--dry-run] [--json]
      opendisplay reconnect <selector> [--json]
      opendisplay recover [--json]

    SELECTORS: id:<recordID> · main · builtin · state:<active|managedOffline> · <cgDisplayID>
    """)
default:
    fail("unknown command '\(command)' (try: list, diagnose, disconnect, reconnect, recover, help)", code: 2)
}
