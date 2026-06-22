#if os(macOS)
import AppIntents
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import ProviderInterfaces
import TopologyCore
#if !PUBLIC_API_ONLY
import ExperimentalLifecycleProvider
#endif

/// Shortcuts / Siri integration (PRD §1 automation, recovery hierarchy step 3). Every intent routes
/// through the same `CommandGateway` the menu bar and CLI use, so it inherits the full safety,
/// verification, and audit path. Each invocation builds a fresh gateway (the intent may run outside
/// the running app), mirroring the CLI's independent composition.
enum OpenDisplayAutomation {
    static func makeGateway() async -> CommandGateway {
        let observer = CoreGraphicsProvider()
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let environment = ProviderEnvironment(
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString,
            isAppleSilicon: appleSilicon, transport: .unknown, displayClass: .unknown
        )
        let lifecycle: any LifecycleProvider
        #if !PUBLIC_API_ONLY
        let experimental = ExperimentalLifecycleProvider()
        lifecycle = await experimental.probe(environment).status == .supported ? experimental : observer
        #else
        lifecycle = observer
        #endif
        let checkpoints: any CheckpointStoring =
            (try? DiskCheckpointStore.defaultDirectory()).map(DiskCheckpointStore.init(directory:))
            ?? InMemoryCheckpointStore()
        let audit = (try? DiskAuditLog.defaultDirectory()).map(DiskAuditLog.init(directory:))
        return CommandGateway(observer: observer, lifecycleProvider: lifecycle,
                              checkpoints: checkpoints, auditLog: audit)
    }
}

/// Reconnects every managed-offline display — the always-available recovery action, now usable from
/// Shortcuts, Siri, and the Shortcuts menu-bar surface.
struct ReconnectAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Reconnect All Displays"
    static let description = IntentDescription(
        "Reconnects every OpenDisplay-managed offline display — the always-available recovery action."
    )
    // The intent does its own work; no need to bring the app forward.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let envelope = await OpenDisplayAutomation.makeGateway().reconnectAll(actor: .appIntent)
        let restored = envelope.targets.filter { target in
            target.operations.contains { $0.verification == .verified }
        }.count
        let message = restored == 0
            ? "No displays needed reconnecting."
            : "Reconnected \(restored) display\(restored == 1 ? "" : "s")."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct OpenDisplayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReconnectAllIntent(),
            phrases: [
                "Reconnect all displays with \(.applicationName)",
                "\(.applicationName) reconnect all displays"
            ],
            shortTitle: "Reconnect All",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
#endif
