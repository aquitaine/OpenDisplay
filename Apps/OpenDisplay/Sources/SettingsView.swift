#if os(macOS)
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// Settings window. A sidebar (Displays · Arrange · Scenes · Health & Recovery) replaces the old
/// 3-tab shell: "Displays" is now a selection list feeding a per-display detail pane (so the topology
/// isn't duplicated with the menu bar), "Arrange" is promoted out of Scenes into its own item, and
/// diagnostics/recovery/Labs are unified under "Health & Recovery". See `Docs/InterfaceRedesign.md`.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: SettingsSection? = .displays

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch section ?? .displays {
            case .displays: DisplaysSection()
            case .arrange: ArrangeSection()
            case .scenes: ScenesSection()
            case .health: HealthSection()
            }
        }
        .frame(minWidth: 720, idealWidth: 720, minHeight: 480, idealHeight: 520)
        .task {
            await model.refreshDiagnostics()
            await model.refreshActivity()
        }
        // Deep-link from the menu bar's "Display settings…": jump to the Displays section so the
        // selected display is shown even if Settings was already open on another section.
        .onChange(of: model.selectedDisplayID) { _, newValue in
            if newValue != nil { section = .displays }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case displays, arrange, scenes, health
    var id: String { rawValue }
    var title: String {
        switch self {
        case .displays: return "Displays"
        case .arrange: return "Arrange"
        case .scenes: return "Scenes"
        case .health: return "Health & Recovery"
        }
    }
    var icon: String {
        switch self {
        case .displays: return "display"
        case .arrange: return "rectangle.3.group"
        case .scenes: return "square.stack.3d.up"
        case .health: return "stethoscope"
        }
    }
}

// MARK: - Displays (selection list → detail pane)

private struct DisplaysSection: View {
    @EnvironmentObject private var model: AppModel

    private var selected: DisplayObservation? {
        model.displays.first { $0.recordID == model.selectedDisplayID }
            ?? model.displays.first { $0.isMain }
            ?? model.displays.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.displays.isEmpty {
                ContentUnavailableView("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
            } else {
                if model.displays.count > 1 {
                    Picker("", selection: Binding(
                        get: { selected?.recordID ?? model.displays.first?.recordID },
                        set: { model.selectedDisplayID = $0 })) {
                        ForEach(model.displays, id: \.recordID) { display in
                            Text(model.displayName(for: display)).tag(Optional(display.recordID))
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .padding(.horizontal, 16).padding(.top, 16)
                }
                if let display = selected {
                    DisplayDetailView(display: display)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Displays")
    }
}

// MARK: - Arrange

private struct ArrangeSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ODSpacing.md) {
                DisplayArrangementView()
                Text("Drag a display to reposition it. Changes apply immediately; save the layout as a scene under Scenes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(ODSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Arrange Displays")
    }
}

// MARK: - Scenes

private struct ScenesSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ODSpacing.md) {
                if let warning = model.sceneWarning {
                    ODInlineBanner(tone: .orange, systemImage: "exclamationmark.triangle", title: warning)
                }
                if model.scenes.isEmpty {
                    Text("No saved scenes yet. Arrange your displays, then save the current arrangement below.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ODCard {
                        ForEach(Array(model.scenes.enumerated()), id: \.element.id) { index, scene in
                            if index > 0 { ODDivider() }
                            ODRow(scene.name, secondary: "\(scene.members.count) displays") {
                                HStack(spacing: 8) {
                                    Button("Apply") { Task { await model.applyScene(scene) } }
                                        .controlSize(.small).disabled(model.busy)
                                    Button(role: .destructive) {
                                        Task { await model.deleteScene(scene) }
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                SaveSceneRow()
            }
            .padding(ODSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Scenes")
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

// MARK: - Health & Recovery (diagnostics + recovery + Labs + activity)

private struct HealthSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
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
                        if row.experimental { ODBadge("Labs", tone: .orange) }
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

                Text("Behavior").font(.title3)
                Toggle(isOn: Binding(
                    get: { model.settings.preventDisplaySleepWithExternal },
                    set: { model.setPreventDisplaySleepWithExternal($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep displays awake while an external is connected")
                        Text("Holds a system \u{201C}prevent display sleep\u{201D} assertion whenever at least one "
                             + "external display is present, so the screens don\u{2019}t idle-dim during a "
                             + "presentation or always-on setup. Released automatically when the last external "
                             + "is disconnected.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                #if !PUBLIC_API_ONLY
                Divider()

                Text("Labs").font(.title3)
                Toggle(isOn: $model.experimentalRotationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Experimental display rotation")
                        Text("Rotate displays via a private API. Off by default; runs through a safety-checked, "
                             + "isolated helper with automatic rollback, and is excluded from App Store builds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                #endif

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
        .navigationTitle("Health & Recovery")
    }
}

// MARK: - Arrange canvas (drag-to-position)

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
#endif
