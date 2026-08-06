import XCTest
import AutomationSchema
import DisplayDomain
import ProviderInterfaces
import SimulatorProvider
@testable import TopologyCore

final class CommandGatewayTests: XCTestCase {
    private func obs(_ id: String, active: Bool = true, main: Bool = false,
                     klass: DisplayClass = .external) -> DisplayObservation {
        DisplayObservation(recordID: .init(rawValue: id), isActive: active, isMain: main,
                           displayClass: klass, generation: .initial)
    }

    private func offline(_ id: String) -> ManagedOfflineRecord {
        ManagedOfflineRecord(displayID: .init(rawValue: id), actor: .ui, reason: "test",
                             providerID: "simulator.lifecycle.v1")
    }

    func testReconnectAllReenablesManagedOffline() async {
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("ext", active: false)],
            managedOffline: [offline("ext")]
        )
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.reconnectAll(actor: .cli)
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.actor, .cli)
        XCTAssertEqual(envelope.targets.map(\.displayId), ["ext"])
        XCTAssertEqual(envelope.targets.first?.operations.first?.verification, .verified)
        XCTAssertEqual(envelope.schemaVersion, ResultEnvelope.currentSchemaVersion)
    }

    func testReconnectAllNoOpWhenNothingOffline() async {
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn)])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.reconnectAll()
        XCTAssertEqual(envelope.status, .noOp)
        XCTAssertTrue(envelope.targets.isEmpty)
    }

    func testReconnectAllPartialWhenSomeFail() async {
        // "ext" exists (reconnect succeeds); the "ghost" managed-offline record has no matching
        // observation, so its reconnect throws and is reported false → overall partial.
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("ext", active: false)],
            managedOffline: [offline("ext"), offline("ghost")]
        )
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.reconnectAll()
        XCTAssertEqual(envelope.status, .partial)
        let verification = Dictionary(uniqueKeysWithValues:
            envelope.targets.map { ($0.displayId, $0.operations.first?.verification) })
        XCTAssertEqual(verification["ext"], .verified)
        XCTAssertEqual(verification["ghost"], .readBackUnavailable)
    }

    func testDisconnectCommitsWhenSafeSurfaceRemains() async {
        // Default confirm handler declines, so reaching .committed proves preflight returned
        // .allowed (no confirmation needed) for a non-main target with the built-in as safe surface.
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.disconnect(.init(rawValue: "ext"),
                                                options: DisconnectOptions(actor: .cli, identityConfidence: 1.0))
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.targets.first?.operations.first?.verification, .verified)
    }

    func testDisconnectBlockedWhenRemovingLastSafeDisplay() async {
        let system = SimulatedDisplaySystem(observations: [obs("only", main: true, klass: .builtIn)])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system, checkpoints: InMemoryCheckpointStore())
        let envelope = await gateway.disconnect(.init(rawValue: "only"),
                                                options: DisconnectOptions(actor: .cli, identityConfidence: 1.0))
        XCTAssertEqual(envelope.status, .failed)
        XCTAssertTrue(envelope.errors.contains { $0.code == "blocked" })
    }

    func testPreflightAllowedAndBlocked() async {
        let pair = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let gateway = CommandGateway(observer: pair, lifecycleProvider: pair, checkpoints: InMemoryCheckpointStore())
        let allowed = await gateway.preflightDisconnect(.init(rawValue: "ext"), identityConfidence: 1.0)
        XCTAssertEqual(allowed.decision, .allowed)
        XCTAssertEqual(allowed.safeSurface, DisplayRecordID(rawValue: "builtin"))

        let single = SimulatedDisplaySystem(observations: [obs("only", main: true, klass: .builtIn)])
        let gateway2 = CommandGateway(observer: single, lifecycleProvider: single, checkpoints: InMemoryCheckpointStore())
        let blocked = await gateway2.preflightDisconnect(.init(rawValue: "only"), identityConfidence: 1.0)
        XCTAssertEqual(blocked.decision, .blocked)
        XCTAssertNil(blocked.safeSurface)
    }

    func testCommandsAreRecordedToAuditLog() async {
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn)])
        let audit = InMemoryAuditLog()
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore(), auditLog: audit)
        _ = await gateway.reconnectAll(actor: .cli)
        let entries = await audit.all
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.command, "reconnectAll")
        XCTAssertEqual(entries.first?.actor, .cli)
        XCTAssertEqual(entries.first?.status, "noOp")
    }

    func testLayoutProtectCapturesTheCurrentSetAndIsAudited() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-layout-gateway-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let audit = InMemoryAuditLog()
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore(), auditLog: audit)

        let envelope = await gateway.applyLayoutProtection(.protect, store: store,
                                                          managedOffline: [], actor: .cli)
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.targets.map(\.displayId), ["builtin", "ext"])

        let snapshot = await system.currentSnapshot()
        XCTAssertNotNil(LayoutProtectionPolicy.protectedLayout(
            for: snapshot, managedOffline: [], in: store.load().protectedLayouts))
        let entries = await audit.all
        XCTAssertEqual(entries.map(\.command), ["layoutProtect"])
        XCTAssertEqual(entries.first?.status, "committed")
    }

    /// The CLI protects what the app looks up. A switched-off display is absent from the
    /// enumeration, so if the gateway keyed on the enumeration alone the CLI would file the layout
    /// under one display set and the app — which folds its ledger into the key — would look for it
    /// under another, and `layout protect` would appear to do nothing at all.
    func testLayoutProtectKeysOnTheSameDisplaySetTheAppLooksUpWithASwitchedOffDisplay() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-layout-gateway-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        // The built-in is logically disabled, so it isn't enumerated — the ledger is all we have.
        let system = SimulatedDisplaySystem(observations: [obs("ext", main: true)])
        let ledger = [ManagedOfflineDisplay(recordID: .init(rawValue: "builtin"), cgID: 1,
                                            name: "Built-in", displayClass: .builtIn)]
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore())

        let envelope = await gateway.applyLayoutProtection(.protect, store: store,
                                                           managedOffline: ledger)
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.targets.map(\.displayId), ["builtin", "ext"])

        let snapshot = await system.currentSnapshot()
        let stored = LayoutProtectionPolicy.protectedLayout(
            for: snapshot, managedOffline: [.init(rawValue: "builtin")],
            in: store.load().protectedLayouts)
        XCTAssertNotNil(stored, "the app must find the layout the CLI just protected")
        XCTAssertEqual(stored.map { LayoutProtectionPolicy.desiredOff(in: $0.snapshot) },
                       [.init(rawValue: "builtin")])
    }

    func testLayoutUnprotectRemovesOnlyTheCurrentSetAndNoOpsWhenUnprotected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-layout-gateway-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        // Another display set's protection is already stored; unprotecting here must leave it alone.
        var seeded = OpenDisplaySettings.default
        let otherSet = TopologySnapshot(generation: .initial, observations: [obs("laptop-alone")])
        let otherProtection = LayoutProtectionPolicy.capture(otherSet, at: Date())
        seeded.protectedLayouts = [otherProtection.fingerprint: otherProtection.config]
        try store.save(seeded)

        let system = SimulatedDisplaySystem(
            observations: [obs("builtin", main: true, klass: .builtIn), obs("ext")])
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore())
        let nothingToRemove = await gateway.applyLayoutProtection(.unprotect, store: store,
                                                                  managedOffline: [])
        XCTAssertEqual(nothingToRemove.status, .noOp)

        _ = await gateway.applyLayoutProtection(.protect, store: store, managedOffline: [])
        XCTAssertEqual(store.load().protectedLayouts.count, 2)
        let removed = await gateway.applyLayoutProtection(.unprotect, store: store, managedOffline: [])
        XCTAssertEqual(removed.status, .committed)
        XCTAssertEqual(store.load().protectedLayouts, [otherProtection.fingerprint: otherProtection.config])
    }

    func testGroupChangesAreAuditedLikeEveryOtherCommand() async {
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn)])
        let audit = InMemoryAuditLog()
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore(), auditLog: audit)
        let envelope = await gateway.recordGroupChange("groupAdd", targets: ["ext"])
        XCTAssertEqual(envelope.status, .committed)
        XCTAssertEqual(envelope.targets.map(\.displayId), ["ext"])
        let entries = await audit.all
        XCTAssertEqual(entries.first?.command, "groupAdd")
        XCTAssertEqual(entries.first?.actor, .cli)
    }

    func testARefusedGroupChangeIsAuditedAsANoOp() async {
        let system = SimulatedDisplaySystem(observations: [obs("builtin", main: true, klass: .builtIn)])
        let audit = InMemoryAuditLog()
        let gateway = CommandGateway(observer: system, lifecycleProvider: system,
                                     checkpoints: InMemoryCheckpointStore(), auditLog: audit)
        let envelope = await gateway.recordGroupChange("groupCreate", targets: [], committed: false)
        XCTAssertEqual(envelope.status, .noOp)
        let entries = await audit.all
        XCTAssertEqual(entries.first?.status, "noOp")
    }

    func testEnvelopeMappingCoversEveryResult() {
        let target = DisplayRecordID(rawValue: "d")
        let tx = TransactionID(rawValue: "txn_1")
        func status(_ result: LifecycleResult) -> ResultEnvelope.Status {
            CommandGateway.envelope(for: result, target: target, actor: .cli, generation: 5).status
        }
        XCTAssertEqual(status(.committed(tx, verification: .verified)), .committed)
        XCTAssertEqual(status(.noOp(tx)), .noOp)
        XCTAssertEqual(status(.cancelled(tx)), .noOp)
        XCTAssertEqual(status(.rolledBack(tx, recovered: true)), .rolledBack)
        XCTAssertEqual(status(.failed(tx, .denied)), .failed)
        XCTAssertEqual(status(.blocked([.noSafeSurface])), .failed)
    }
}
