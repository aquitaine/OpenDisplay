#if os(macOS)
import OpenDisplayDesignSystem
import SwiftUI

/// Settings window. The full sidebar (Displays · Arrange · Scenes · Automation · Health & Recovery
/// · Labs) from the design kit is built out across M1–M3; today it surfaces the live topology and
/// the diagnostics + recovery affordances that exist.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            displaysTab
                .tabItem { Label("Displays", systemImage: "display") }
            diagnosticsTab
                .tabItem { Label("Diagnostics & Recovery", systemImage: "stethoscope") }
        }
        .frame(width: 520, height: 360)
    }

    private var displaysTab: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            Text("Connected Displays").font(.title3)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary)
            Divider()
            ForEach(model.displays, id: \.recordID) { display in
                HStack(spacing: ODSpacing.sm) {
                    Circle()
                        .fill(display.isActive ? ODColor.connected : ODColor.caution)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName(for: display))
                        if let mode = display.mode {
                            Text("\(mode.pixelWidth)×\(mode.pixelHeight) @ \(Int(mode.refreshHz.rounded())) Hz")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if display.isMain {
                        Text("Main").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text(display.isActive ? "Active" : "Managed offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(ODSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ODSpacing.md) {
                Text("Providers").font(.title3)
                ForEach(model.diagnostics) { row in
                    HStack(spacing: ODSpacing.sm) {
                        Image(systemName: row.status == "supported" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(row.status == "supported" ? ODColor.connected : ODColor.caution)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.provider)
                            Text("\(row.status) · risk \(row.risk)\(row.reasons.isEmpty ? "" : " · \(row.reasons.joined(separator: ", "))")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if row.experimental {
                            Text("Labs").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                    }
                }

                Divider()

                Text("Recovery").font(.title3)
                LabeledContent("Persistence policy", value: model.settings.persistencePolicy.rawValue)
                LabeledContent("Global hotkey",
                               value: model.settings.reconnectAllHotkeyEnabled ? model.reconnectAllHotkey : "disabled")
                LabeledContent("Checkpoints", value: model.checkpointLocation)
                Button {
                    Task { await model.reconnectAll() }
                } label: {
                    Label("Reconnect All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.busy)

                Divider()

                Text("Recent Activity").font(.title3)
                if model.recentActivity.isEmpty {
                    Text("No recorded activity yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.recentActivity.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: ODSpacing.sm) {
                            Text(entry.command).font(.caption).bold()
                            Text(entry.status).font(.caption).foregroundStyle(.secondary)
                            if !entry.targets.isEmpty {
                                Text(entry.targets.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(ODSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await model.refreshDiagnostics()
            await model.refreshActivity()
        }
    }
}
#endif
