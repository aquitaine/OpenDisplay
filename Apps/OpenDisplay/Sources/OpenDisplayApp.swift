#if os(macOS)
import AppKit
import SwiftUI

/// Menu-bar-first entry point (PRD UX-001). `LSUIElement` keeps it out of the Dock; the primary
/// surface is the menu-bar popover, with a Settings window for detail. The full surface set
/// (topology, scenes, automation, health & recovery, Labs) lands in M1–M3.
@main
struct OpenDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OpenDisplay", systemImage: "display") {
            MenuBarView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// Receives `opendisplay://` URL-scheme activations (Issue 4). A menu-bar (`LSUIElement`) app has no
/// always-alive window to host SwiftUI's `.onOpenURL`, so the URL surface lives on the app delegate.
/// Routing, safety gating, and audit all happen in `OpenDisplayAutomation.handleURL`; the live
/// `AppModel` picks up any resulting topology change through its own reconfiguration stream.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await OpenDisplayAutomation.handleURL(url) }
        }
    }
}
#endif
