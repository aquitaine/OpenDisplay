#if os(macOS)
import SwiftUI

/// Menu-bar-first entry point (PRD UX-001). `LSUIElement` keeps it out of the Dock; the primary
/// surface is the menu-bar popover, with a Settings window for detail. The full surface set
/// (topology, scenes, automation, health & recovery, Labs) lands in M1–M3.
@main
struct OpenDisplayApp: App {
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
#endif
