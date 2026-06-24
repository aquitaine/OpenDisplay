#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

/// Floating "Keep these display settings?" confirmation for the timed auto-revert gate (Issue 6).
///
/// Replaces the earlier menu-bar-popover banner, which only appeared while the popover happened to be
/// open and on whatever display hosted it — so a resolution change made from the Settings window (the
/// gate's primary case) showed no prompt at all, and a set-main showed it on whichever display the
/// menu was opened from rather than anywhere deliberate.
///
/// This panel floats above everything, appears no matter where the change was triggered, and is placed
/// on the display being changed (the one the user is acting on). The auto-revert still covers the case
/// where that display is unreadable — it needs no interaction at all, so an unseen prompt just lapses
/// and the prior arrangement is restored.
@MainActor
final class RevertConfirmationPresenter {
    private var panel: NSPanel?

    /// Show (or reposition) the confirmation for `model.pendingRevert`, anchored to the top-right of
    /// the changed display — just under the menu bar, next to the OpenDisplay status item, so it's
    /// where the user's attention already is and isn't lost in the middle of a busy screen. The hosted
    /// SwiftUI view observes `model`, so the countdown updates itself.
    func show(model: AppModel, changedDisplayID: CGDirectDisplayID?) {
        guard let screen = Self.screen(for: changedDisplayID) else { return }
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 150)
        let visible = screen.visibleFrame  // excludes the menu bar and Dock
        let margin: CGFloat = 12
        let origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Dismiss the confirmation (on keep, revert, or auto-revert).
    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let hosting = NSHostingView(rootView: RevertPromptView().environmentObject(model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "OpenDisplay"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Show on whatever Space is active on the target display, and stay above full-screen apps.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = hosting
        return panel
    }

    /// The `NSScreen` for `displayID`, or the main/first screen as a fallback.
    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        let screens = NSScreen.screens
        if let id = displayID, let match = screens.first(where: { screenNumber($0) == id }) {
            return match
        }
        return NSScreen.main ?? screens.first
    }

    private static func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Contents of the floating revert confirmation. Bound to `AppModel.pendingRevert` so the countdown
/// ticks live; the buttons drive the same `confirmArrangementChange()` / `revertArrangementChange()`
/// the gate already exposes.
private struct RevertPromptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let pending = model.pendingRevert
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep these display settings?", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if let pending {
                Text(pending.message)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reverting in \(pending.secondsRemaining) second\(pending.secondsRemaining == 1 ? "" : "s")…")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Button("Revert Now") { Task { await model.revertArrangementChange() } }
                Spacer()
                Button("Keep") { model.confirmArrangementChange() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
#endif
