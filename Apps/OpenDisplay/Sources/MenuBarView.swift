#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// The menu-bar popover (primary surface). Ports a subset of the designed states from the design
/// kit: scanning, ready (the display list), empty, reconnecting (busy), and a degraded banner when
/// a provider is unavailable. The remaining states (managed-offline detail, ambiguous identity, …)
/// land as the topology surface fills in (M1–M2).
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            header
            Divider()
            content
            if model.isDegraded { degradedBanner }
            Divider()
            actions
        }
        .padding(ODSpacing.md)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("OpenDisplay").font(.headline)
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
            }
            Text(model.busy ? "Reconnecting…" : model.statusText)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .scanning:
            HStack(spacing: ODSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Scanning displays…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .empty:
            Label("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
                .foregroundStyle(.secondary)
        case .ready:
            ForEach(model.displays, id: \.recordID) { display in
                HStack(spacing: ODSpacing.sm) {
                    Circle()
                        .fill(display.isActive ? ODColor.connected : ODColor.caution)
                        .frame(width: 8, height: 8)
                    Text(model.displayName(for: display))
                    if display.isMain {
                        Text("Main").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(display.isActive ? "Active" : "Managed offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var degradedBanner: some View {
        Label("Some providers are unavailable", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(ODColor.caution)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        Group {
            Button {
                Task { await model.reconnectAll() }
            } label: {
                Label(model.busy ? "Reconnecting…" : "Reconnect All",
                      systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(ODColor.accent)
            .disabled(model.busy)

            Button("Display Settings…") { showSettings() }
            Button("Quit OpenDisplay") { NSApp.terminate(nil) }
        }
    }

    /// Opens Settings and brings the window to the display the user is actually looking at. With
    /// "Displays have separate Spaces" the SwiftUI Settings window opens on the main display's
    /// Space, so clicking the menu bar on an extended display otherwise appears to do nothing.
    private func showSettings() {
        openSettingsAction()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let window = NSApp.windows.first(where: {
                $0.styleMask.contains(.titled) && $0.canBecomeMain
            }) else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if let screen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }) {
                let visible = screen.visibleFrame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                              y: visible.midY - size.height / 2))
            }
        }
    }
}
#endif
