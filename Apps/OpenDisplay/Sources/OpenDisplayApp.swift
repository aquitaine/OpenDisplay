#if os(macOS)
import AppKit
import SwiftUI

/// Menu-bar-first entry point (PRD UX-001). `LSUIElement` keeps it out of the Dock. The menu bar AND
/// the Settings window are both AppKit-managed by `AppDelegate`: SwiftUI's `MenuBarExtra` mis-anchors
/// its pop-out across multiple displays, and a menu-bar app can't reliably surface SwiftUI's `Settings`
/// scene through the responder chain — so the delegate hosts `SettingsView` in its own `NSWindow` and
/// owns the shared `AppModel`. The placeholder scene below only satisfies `App`'s scene requirement; it
/// never auto-opens.
@main
struct OpenDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
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
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = false
        let controller = NSHostingController(rootView: MenuBarView().environmentObject(model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller

        // Close the pop-out when an action that re-lays-out the displays is picked (e.g. Set as Main):
        // otherwise the open pop-out, anchored to the status item, gets displaced to a random spot when
        // set-main relocates the menu bar to the new main display.
        NotificationCenter.default.addObserver(
            self, selector: #selector(dismissPopover), name: .openDisplayDismissMenu, object: nil)
        // The menu's gear / "Displays & arrangement…" rows ask the delegate to open Settings (we own
        // that window, not SwiftUI) so it reliably appears on the screen the user is looking at.
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings), name: .openDisplayShowSettings, object: nil)

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

    @objc private func dismissPopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// Opens (or re-focuses) the Settings window on the screen the user is looking at. Hosting it in our
    /// own `NSWindow` — rather than SwiftUI's `Settings` scene — is the only reliable way to surface and
    /// position it from a menu-bar (LSUIElement) app, especially with "Displays have separate Spaces".
    @objc private func showSettings() {
        dismissPopover()
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(model))
            let created = NSWindow(contentViewController: hosting)
            created.title = "OpenDisplay Settings"
            created.styleMask = [.titled, .closable, .miniaturizable]
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 720, height: 520))
            settingsWindow = created
            window = created
        }
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                          y: visible.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Returns the Mac to a clean default on quit. Reconnecting a display the app turned off is async
    /// (CoreGraphics reconfiguration), so when there's something to undo we defer termination until the
    /// revert completes; otherwise quit immediately. Gamma and the keep-awake assertion are also
    /// restored synchronously by `AppModel`'s `willTerminate` backstop.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.needsQuitReversion else { return .terminateNow }
        Task {
            await model.teardownForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await OpenDisplayAutomation.handleURL(url) }
        }
    }
}

extension Notification.Name {
    /// Posted by a menu action that re-lays-out the displays (e.g. Set as Main) so the app delegate
    /// closes the pop-out before the menu bar relocates and displaces it.
    static let openDisplayDismissMenu = Notification.Name("OpenDisplayDismissMenu")
    /// Posted by the menu's gear / "Displays & arrangement…" rows to ask the delegate to open the
    /// Settings window (AppKit-owned, so it lands on the screen the user clicked from).
    static let openDisplayShowSettings = Notification.Name("OpenDisplayShowSettings")
}
#endif
