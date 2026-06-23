#if os(macOS)
import DisplayDomain
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
            scenesTab
                .tabItem { Label("Scenes", systemImage: "rectangle.3.group") }
            diagnosticsTab
                .tabItem { Label("Diagnostics & Recovery", systemImage: "stethoscope") }
        }
        .frame(width: 560, height: 440)
    }

    private var scenesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ODSpacing.md) {
                Text("Saved Scenes").font(.title3)
                if let warning = model.sceneWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(ODColor.caution)
                }
                if model.scenes.isEmpty {
                    Text("No saved scenes yet. Arrange your displays below, then save.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(model.scenes) { scene in
                        HStack(spacing: ODSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.name)
                                Text("\(scene.members.count) displays").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Apply") { Task { await model.applyScene(scene) } }
                                .disabled(model.busy)
                            Button(role: .destructive) {
                                Task { await model.deleteScene(scene) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Divider()
                SaveSceneRow()
                DisplayArrangementView()
                Text("Drag a display to reposition it. Changes apply immediately; save to keep the layout as a scene.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(ODSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private struct SaveSceneRow: View {
        @EnvironmentObject private var model: AppModel
        @State private var name = ""

        var body: some View {
            HStack(spacing: ODSpacing.sm) {
                TextField("New scene name", text: $name).textFieldStyle(.roundedBorder)
                Button("Save Current Arrangement") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    Task { await model.saveScene(named: trimmed); name = "" }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// One display row with an editable alias. The placeholder shows the resolved name (OS name or
    /// existing alias); the field edits the user alias, committed to the registry on submit.
    private struct DisplayRow: View {
        @EnvironmentObject private var model: AppModel
        let display: DisplayObservation
        @State private var alias = ""

        var body: some View {
            HStack(spacing: ODSpacing.sm) {
                Circle()
                    .fill(display.isActive ? ODColor.connected : ODColor.caution)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(model.displayName(for: display), text: $alias)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { Task { await model.setAlias(alias, for: display) } }
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
            .onAppear { alias = model.records[display.recordID]?.alias ?? "" }
        }
    }

    /// The drag-to-arrange canvas: each active display is a proportionally-sized, positioned tile
    /// (mirroring System Settings › Displays › Arrange). Dropping a tile applies its new origin live;
    /// Core Graphics then re-snaps the layout so displays stay adjacent and the canvas re-renders.
    private struct DisplayArrangementView: View {
        @EnvironmentObject private var model: AppModel
        private let canvas = CGSize(width: 480, height: 210)

        var body: some View {
            let tiles = model.displays.compactMap { display -> (DisplayObservation, CGRect)? in
                guard let mode = display.mode, display.isActive else { return nil }
                return (display, CGRect(x: CGFloat(display.origin.x), y: CGFloat(display.origin.y),
                                        width: CGFloat(mode.pointWidth), height: CGFloat(mode.pointHeight)))
            }
            let union = tiles.map(\.1).reduce(CGRect.null) { $0.union($1) }
            let scale: CGFloat = (union.isNull || union.width < 1 || union.height < 1)
                ? 0.05
                : min(canvas.width / union.width, canvas.height / union.height) * 0.82

            return ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
                ForEach(tiles, id: \.0.recordID) { display, frame in
                    DisplayTile(
                        display: display,
                        tileSize: CGSize(width: frame.width * scale, height: frame.height * scale),
                        center: CGPoint(x: (frame.midX - union.midX) * scale + canvas.width / 2,
                                        y: (frame.midY - union.midY) * scale + canvas.height / 2),
                        scale: scale)
                }
            }
            .frame(width: canvas.width, height: canvas.height)
        }
    }

    private struct DisplayTile: View {
        @EnvironmentObject private var model: AppModel
        let display: DisplayObservation
        let tileSize: CGSize
        let center: CGPoint
        let scale: CGFloat
        @State private var drag: CGSize = .zero

        var body: some View {
            let tint = display.isMain ? Color.accentColor : Color.secondary
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint, lineWidth: display.isMain ? 2 : 1))
                .overlay(
                    VStack(spacing: 1) {
                        Text(model.displayName(for: display)).font(.caption2).lineLimit(1).padding(.horizontal, 3)
                        if display.isMain { Text("Main").font(.system(size: 8)).foregroundStyle(.secondary) }
                    }
                )
                .frame(width: max(tileSize.width, 36), height: max(tileSize.height, 24))
                .position(x: center.x + drag.width, y: center.y + drag.height)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let dx = Int((value.translation.width / scale).rounded())
                            let dy = Int((value.translation.height / scale).rounded())
                            drag = .zero
                            guard dx != 0 || dy != 0 else { return }
                            let origin = DisplayOrigin(x: display.origin.x + dx, y: display.origin.y + dy)
                            Task { await model.setPosition(origin, for: display) }
                        }
                )
        }
    }

    private var displaysTab: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            Text("Connected Displays").font(.title3)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary)
            Divider()
            ForEach(model.displays, id: \.recordID) { display in
                DisplayRow(display: display)
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
