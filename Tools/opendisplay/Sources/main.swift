import AutomationSchema
import CoreGraphicsProvider
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation
import ProviderInterfaces
import TopologyCore

// OpenDisplay automation CLI (PRD §12). Runs real commands through the same platform-independent
// core the UI uses: live Core Graphics enumeration, the safety-checked TopologyCoordinator, and a
// stable JSON result envelope. `disconnect --dry-run` previews the SafetyEngine decision without
// touching hardware. Selector grammar per DisplaySelector (PRD §12.3).

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

// MARK: - Composition root (real providers, shared on-disk checkpoints)

let observer = CoreGraphicsProvider()
let environment = ProviderEnvironment(
    osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
    isAppleSilicon: isAppleSilicon, transport: .unknown, displayClass: .unknown
)
// Prefer the experimental SkyLight provider when its probe reports supported; otherwise the public
// mirroring provider. Probe status is a value comparison, so it is safe across framework images.
let experimental = ExperimentalLifecycleProvider()
let lifecycle: any LifecycleProvider =
    await experimental.probe(environment).status == .supported ? experimental : observer
let checkpoints: any CheckpointStoring =
    (try? DiskCheckpointStore.defaultDirectory()).map(DiskCheckpointStore.init(directory:))
    ?? InMemoryCheckpointStore()
let coordinator = TopologyCoordinator(
    observer: observer, lifecycleProvider: lifecycle, checkpoints: checkpoints
)

// MARK: - Selector resolution (against live observations)

func reachability(of observation: DisplayObservation, managedOffline: Set<DisplayRecordID>) -> Reachability {
    if managedOffline.contains(observation.recordID) { return .managedOffline }
    return observation.isActive ? .active : .discoveredInactive
}

func resolve(_ raw: String, in snapshot: TopologySnapshot) throws -> [DisplayObservation] {
    // Convenience: a bare integer matches a CGDirectDisplayID.
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
        // alias/tag/name/fingerprint/topology resolution needs the persisted DisplayRegistry,
        // which isn't wired into the CLI yet; id/main/builtin/state/<cgID> are supported today.
        fail("selector '\(raw)' isn't resolvable yet from live observations (use id:/main/builtin/state:/<cgID>)")
    }
}

// MARK: - Output payloads

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
        let reasons = probe.reasons.isEmpty ? "" : " (\(probe.reasons.map(\.rawValue).joined(separator: ",")))"
        print("\(id)\(labsTag): \(probe.status.rawValue) · risk=\(probe.risk.rawValue)\(reasons)")
    }
}

func envelope(_ status: ResultEnvelope.Status, txID: String, generation: UInt64,
              targets: [ResultEnvelope.TargetResult] = [], errors: [ResultEnvelope.ErrorInfo] = []) -> ResultEnvelope {
    ResultEnvelope(transactionId: txID, status: status, actor: .cli, requestedAt: Date(),
                   topologyGeneration: generation, targets: targets, errors: errors)
}

func runRecover() async {
    let results = await coordinator.reconnectAll()
    let snapshot = await observer.currentSnapshot()
    let targets = results.sorted { $0.key.rawValue < $1.key.rawValue }.map { id, ok in
        ResultEnvelope.TargetResult(
            displayId: id.rawValue, alias: nil, identityConfidence: 1.0,
            operations: [.init(field: "reconnect", verification: ok ? .verified : .readBackUnavailable)]
        )
    }
    let status: ResultEnvelope.Status = results.isEmpty ? .noOp : (results.values.allSatisfy { $0 } ? .committed : .partial)
    if asJSON {
        emit(envelope(status, txID: "txn_recover", generation: snapshot.generation.value, targets: targets))
    } else {
        print(results.isEmpty ? "recover: nothing to reconnect" :
            results.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.value ? "reconnected" : "failed     ") \($0.key.rawValue)" }.joined(separator: "\n"))
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

func runDisconnect() async {
    guard let selectorArg else { fail("usage: opendisplay disconnect <selector> [--dry-run] [--json]") }
    let snapshot = await observer.currentSnapshot()
    let target = uniqueTarget(selectorArg, in: snapshot)

    if dryRun {
        // Preview only — never touches hardware. Reports the SafetyEngine preflight decision.
        let decision = SafetyEngine().preflightDisconnect(
            target: target.recordID, snapshot: snapshot, identityConfidence: 1.0,
            recoveryServiceHealthy: true, isFirstUseForRoute: false
        )
        switch decision {
        case .allowed(let surface):
            print("dry-run: ALLOWED — would disconnect \(target.recordID.rawValue); safe surface = \(surface.rawValue)")
        case .needsConfirmation(let surface, let reasons):
            print("dry-run: NEEDS CONFIRMATION (\(reasons.map(\.rawValue).joined(separator: ","))) — safe surface = \(surface.rawValue)")
        case .blocked(let reasons):
            print("dry-run: BLOCKED (\(reasons.map(\.rawValue).joined(separator: ",")))")
        }
        return
    }

    do {
        let result = try await coordinator.disconnect(
            target.recordID, options: DisconnectOptions(actor: .cli, identityConfidence: 1.0)
        )
        let after = await observer.currentSnapshot()
        report(result, target: target.recordID, generation: after.generation.value)
    } catch {
        fail("disconnect failed: \(error)")
    }
}

func runReconnect() async {
    guard let selectorArg else { fail("usage: opendisplay reconnect <selector> [--json]") }
    let snapshot = await observer.currentSnapshot()
    let target = uniqueTarget(selectorArg, in: snapshot)
    do {
        try await lifecycle.reconnect(target.recordID, deadline: Date().addingTimeInterval(15))
        let after = await observer.currentSnapshot()
        if asJSON {
            emit(envelope(.committed, txID: "txn_reconnect", generation: after.generation.value,
                          targets: [.init(displayId: target.recordID.rawValue, alias: nil, identityConfidence: 1.0,
                                          operations: [.init(field: "reconnect", verification: .verified)])]))
        } else {
            print("reconnected \(target.recordID.rawValue)")
        }
    } catch {
        fail("reconnect failed: \(error)")
    }
}

func report(_ result: LifecycleResult, target: DisplayRecordID, generation: UInt64) {
    let status: ResultEnvelope.Status
    var errors: [ResultEnvelope.ErrorInfo] = []
    switch result {
    case .committed: status = .committed
    case .noOp: status = .noOp
    case .rolledBack(_, let recovered):
        status = .rolledBack
        errors = [.init(code: "rolledBack", message: "recovered=\(recovered)")]
    case .blocked(let reasons):
        status = .failed
        errors = reasons.map { .init(code: "blocked", message: "\($0)") }
    case .cancelled:
        status = .noOp
    case .failed(_, let failure):
        status = .failed
        errors = [.init(code: "providerFailure", message: "\(failure)")]
    }
    if asJSON {
        emit(envelope(status, txID: "txn_disconnect", generation: generation,
                      targets: [.init(displayId: target.rawValue, alias: nil, identityConfidence: 1.0,
                                      operations: [.init(field: "disconnect", verification: status == .committed ? .verified : .notApplicable)])],
                      errors: errors))
    } else {
        print("disconnect \(target.rawValue): \(status.rawValue)\(errors.isEmpty ? "" : " (\(errors.map(\.message).joined(separator: "; ")))")")
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
