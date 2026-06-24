#if os(macOS)
import AppKit
import SwiftUI

/// Floating "Keep these display settings?" confirmation for the timed auto-revert gate (Issue 6).
///
/// Replaces the earlier menu-bar-popover banner, which only appeared while that popover happened to be
/// open. This pop-out appears wherever the change was triggered: it's placed on the screen the user is
/// acting on (the one under the cursor — i.e. the screen whose menu-bar icon they just used, or whose
/// Settings slider they dragged) and anchored at the top, just below the menu bar near the cursor. The
/// mouse is already where it needs to be, with no jump to another display. The auto-revert still covers
/// an unreadable display, since it needs no interaction at all.
@MainActor
final class RevertConfirmationPresenter {
    private var panel: NSPanel?

    /// Show (or reposition) the confirmation for `model.pendingRevert`. The hosted SwiftUI view
    /// observes `model`, so the countdown updates itself.
    func show(model: AppModel) {
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        guard let screen = Self.cursorScreen() else { return }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 300, height: 150)
        let visible = screen.visibleFrame  // excludes the menu bar and Dock
        let topGap: CGFloat = 6
        let edge: CGFloat = 8
        // Horizontally centered under the cursor (≈ beneath the menu-bar icon / where the user clicked),
        // clamped fully on-screen; vertically just under the menu bar.
        let cursorX = NSEvent.mouseLocation.x
        let x = min(max(cursorX - size.width / 2, visible.minX + edge), visible.maxX - size.width - edge)
        let y = visible.maxY - size.height - topGap
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    /// Dismiss the confirmation (on keep, revert, or auto-revert).
    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let hosting = NSHostingView(rootView: RevertPromptView().environmentObject(model))
        let panel = KeyabledPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear          // let the SwiftUI rounded card show through
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = hosting
        return panel
    }

    /// The screen currently under the cursor (where the user is acting), or main/first as a fallback.
    private static func cursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
}

/// A borderless panel that can still become key, so the Return-to-Keep shortcut works once clicked.
private final class KeyabledPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Contents of the floating revert confirmation — a compact rounded card. Bound to
/// `AppModel.pendingRevert` so the countdown ticks live; the buttons drive the same
/// `confirmArrangementChange()` / `revertArrangementChange()` the gate already exposes.
private struct RevertPromptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let pending = model.pendingRevert
        VStack(alignment: .leading, spacing: 10) {
            Label("Keep these display settings?", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if let pending {
                Text(pending.message)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reverting in \(pending.secondsRemaining) second\(pending.secondsRemaining == 1 ? "" : "s")…")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Revert Now") { Task { await model.revertArrangementChange() } }
                Button("Keep") { model.confirmArrangementChange() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
#endif
