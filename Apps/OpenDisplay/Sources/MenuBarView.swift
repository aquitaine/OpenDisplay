#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// The menu-bar popover (primary surface). This is a minimal first cut wired to live model data;
/// the 11 designed states (scanning, managed-offline, reconnecting, degraded, ambiguous, …) are
/// ported from the design kit in M1.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            HStack {
                Text("OpenDisplay").font(.headline)
                Spacer()
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            ForEach(model.displays, id: \.recordID) { display in
                HStack(spacing: ODSpacing.sm) {
                    Circle()
                        .fill(display.isActive ? ODColor.connected : ODColor.caution)
                        .frame(width: 8, height: 8)
                    Text(display.recordID.rawValue)
                    if display.isMain {
                        Text("Main").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(display.isActive ? "Active" : "Managed offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                Task { await model.reconnectAll() }
            } label: {
                Label("Reconnect All", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(ODColor.accent)
            .disabled(model.busy)

            Button("Display Settings…") { openSettings() }
            Button("Quit OpenDisplay") { NSApp.terminate(nil) }
        }
        .padding(ODSpacing.md)
        .frame(width: 300)
    }

    /// Opens the Settings scene (selector name is stable on macOS 13+).
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
#endif
