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

/// Sets the built-in display's brightness from Shortcuts / Siri (via the same private DisplayServices
/// path the menu uses). Excluded from the public-API-only build.
struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Brightness"
    static let description = IntentDescription("Sets the built-in display's brightness (0–100%).")
    static let openAppWhenRun = false

    @Parameter(title: "Brightness", inclusiveRange: (0, 100))
    var percent: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clamped = max(0, min(100, percent))
        #if !PUBLIC_API_ONLY
        let observer = CoreGraphicsProvider()
        let snapshot = await observer.currentSnapshot()
        guard let builtIn = snapshot.observations.first(where: { $0.displayClass == .builtIn }),
              let cgID = builtIn.cgDisplayID else {
            return .result(dialog: "No built-in display found.")
        }
        let ok = DisplayServicesBrightnessProvider().setBrightness(Float(clamped) / 100, for: cgID)
        let message = ok ? "Set built-in brightness to \(clamped)%." : "Couldn't set the brightness."
        return .result(dialog: IntentDialog(stringLiteral: message))
        #else
        return .result(dialog: "Brightness control isn't available in this build.")
        #endif
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
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: [
                "Set \(.applicationName) brightness",
                "\(.applicationName) set brightness"
            ],
            shortTitle: "Set Brightness",
            systemImageName: "sun.max"
        )
    }
}
#endif
