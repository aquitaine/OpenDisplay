#if os(macOS)
import AppKit
import SwiftUI

/// Menu-bar-first entry point (PRD UX-001). `LSUIElement` keeps it out of the Dock. The menu bar is
/// driven by AppKit (`NSStatusItem` + `NSPopover`, see `AppDelegate`) rather than SwiftUI's
/// `MenuBarExtra`, which mis-anchors its pop-out across multiple displays. Settings stays a SwiftUI
/// scene; the app delegate owns the shared `AppModel` so both surfaces see the same state.
@main
struct OpenDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(appDelegate.model)
        }
    }
}

/// Owns the menu-bar status item + popover and the shared `AppModel`, and receives `opendisplay://`
/// URL activations (Issue 4).
///
/// Why AppKit instead of `MenuBarExtra`: with several displays, SwiftUI's `MenuBarExtra(.window)`
/// pop-out frequently opens on the *wrong* screen (often the opposite one from the click). An
/// `NSPopover` shown `relativeTo:` the clicked status-item button always anchors below the icon on the
/// screen the user clicked, and — with "Displays have separate Spaces" — stays there even when a
/// set-main changes the primary display. The Keep/Revert confirmation lives inside that pop-out.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = false
        let controller = NSHostingController(rootView: MenuBarView().environmentObject(model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "OpenDisplay")
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await OpenDisplayAutomation.handleURL(url) }
        }
    }
}
#endif
