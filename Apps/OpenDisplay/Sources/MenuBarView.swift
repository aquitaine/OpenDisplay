#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// The menu-bar popover (primary surface), styled after BetterDisplay: a per-display card with an
/// on/off toggle and inline brightness + resolution controls, an expandable per-display action list,
/// a Tools section, and a bottom toolbar. Phase 1 wires the controls that exist today (on/off,
/// resolution, set-as-main, reconnect) and shows the rest as "Soon" until their providers land.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettingsAction
    @State private var expandedID: DisplayRecordID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            if model.isDegraded { degradedBanner }
            Divider().padding(.vertical, 2)
            toolsSection
            bottomToolbar
        }
        .padding(8)
        .frame(width: 322)
        .onChange(of: model.displays.count, initial: true) { _, _ in
            if expandedID == nil { expandedID = model.displays.first(where: { $0.isMain })?.recordID }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .scanning {
            HStack(spacing: ODSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Scanning displays…").foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.displays.isEmpty && model.managedOffline.isEmpty {
            Label("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
                .foregroundStyle(.secondary)
                .padding(8)
        } else {
            ForEach(model.displays, id: \.recordID) { display in
                DisplayCard(display: display, expandedID: $expandedID, onOpenSettings: showSettings)
            }
            ForEach(model.managedOffline) { offline in
                OfflineDisplayCard(offline: offline)
            }
        }
    }

    private var degradedBanner: some View {
        Label("Some providers are unavailable", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(ODColor.caution)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolsSection: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis").font(.system(size: 11))
                Text("Tools").font(.caption)
                Spacer()
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 1)

            MenuActionRow(title: model.busy ? "Reconnecting…" : "Reconnect all",
                          systemImage: "arrow.triangle.2.circlepath", showChevron: false,
                          enabled: !model.busy) { Task { await model.reconnectAll() } }
            MenuActionRow(title: "Displays & arrangement…", systemImage: "rectangle.3.group",
                          showChevron: true) { showSettings() }
            MenuActionRow(title: "Check for updates", systemImage: "arrow.down.circle", soon: true)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Text("OpenDisplay").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button { showSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 14)
            Menu {
                Button("About OpenDisplay") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                Divider()
                Button("Quit OpenDisplay") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
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

/// One display: header (icon · name · main badge · on/off toggle · disclosure), inline brightness
/// and resolution controls, and — when expanded — the per-display action list.
private struct DisplayCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    @Binding var expandedID: DisplayRecordID?
    let onOpenSettings: () -> Void
    @State private var resIndex: Double = 0
    @State private var brightness: Float = 0.5
    @State private var brightnessSupported = false

    private var isExpanded: Bool { expandedID == display.recordID }

    var body: some View {
        let modes = display.isActive ? model.availableModes(for: display) : []
        VStack(alignment: .leading, spacing: 9) {
            header
            if display.isActive {
                brightnessControl
                resolutionControl(modes)
                if isExpanded { actionList }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
        .onAppear {
            resIndex = currentIndex(in: modes)
            syncBrightness()
        }
        .onChange(of: display.mode) { _, _ in resIndex = currentIndex(in: model.availableModes(for: display)) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: display.displayClass == .builtIn ? "laptopcomputer" : "display")
                .font(.system(size: 18)).foregroundStyle(.secondary)
            Text(model.displayName(for: display)).font(.system(size: 14, weight: .medium)).lineLimit(1)
            if display.isMain {
                Text("M").font(.system(size: 10, weight: .medium))
                    .frame(width: 17, height: 17)
                    .overlay(Circle().stroke(ODColor.accent, lineWidth: 1))
                    .foregroundStyle(ODColor.accent)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { display.isActive },
                set: { newValue in Task { await model.setDisplayActive(newValue, for: display) } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(model.busy || (display.isActive && model.activeDisplayCount <= 1))
                .help(display.isActive && model.activeDisplayCount <= 1
                      ? "Can't turn off your only active display"
                      : "Turn display off (logical disconnect)")
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = isExpanded ? nil : display.recordID
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!display.isActive)
            .opacity(display.isActive ? 1 : 0)
        }
    }

    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Brightness").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if brightnessSupported {
                    Text("\(Int((brightness * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Soon").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "sun.max").font(.caption).foregroundStyle(.tertiary)
                if brightnessSupported {
                    Slider(value: $brightness, in: 0...1)
                        .onChange(of: brightness) { _, newValue in model.setBrightness(newValue, for: display) }
                } else {
                    Slider(value: .constant(0.5)).disabled(true).opacity(0.45)
                }
            }
        }
    }

    private func syncBrightness() {
        if let value = model.brightness(for: display) {
            brightness = value
            brightnessSupported = true
        } else {
            brightnessSupported = false
        }
    }

    private func resolutionControl(_ modes: [DisplayMode]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Resolution").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(display.mode.map { "\($0.pointWidth) × \($0.pointHeight)" } ?? "—")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "rectangle.on.rectangle").font(.caption).foregroundStyle(.tertiary)
                if modes.count >= 2 {
                    Slider(value: $resIndex, in: 0...Double(modes.count - 1), step: 1) { editing in
                        guard !editing else { return }
                        let index = Int(resIndex.rounded())
                        guard modes.indices.contains(index) else { return }
                        Task { await model.setMode(modes[index], for: display) }
                    }
                } else {
                    Slider(value: .constant(0)).disabled(true).opacity(0.45)
                }
            }
        }
    }

    private var actionList: some View {
        VStack(spacing: 1) {
            Divider().padding(.vertical, 3)
            if !display.isMain {
                MenuActionRow(title: "Set as main display", systemImage: "star", showChevron: false) {
                    Task { await model.setMain(for: display) }
                }
            }
            MenuActionRow(title: "Mirror display", systemImage: "rectangle.on.rectangle.angled", soon: true)
            MenuActionRow(title: "Move in arrangement…", systemImage: "arrow.up.left.and.arrow.down.right") {
                onOpenSettings()
            }
            MenuActionRow(title: "Screen rotation", systemImage: "rotate.right", soon: true)
            MenuActionRow(title: "Colour mode", systemImage: "paintpalette", soon: true)
            MenuActionRow(title: "Hardware control", systemImage: "slider.horizontal.3", soon: true)
            MenuActionRow(title: "Rename & manage…", systemImage: "tag") { onOpenSettings() }
        }
    }

    private func currentIndex(in modes: [DisplayMode]) -> Double {
        guard let mode = display.mode else { return 0 }
        if let index = modes.firstIndex(where: {
            $0.pointWidth == mode.pointWidth && $0.pointHeight == mode.pointHeight
        }) {
            return Double(index)
        }
        return Double(max(modes.count - 1, 0))
    }
}

/// A display the app has turned off: stays visible (dimmed) with its toggle in the off position so it
/// can be switched back on. The OS no longer enumerates it, so its data comes from AppModel's list.
private struct OfflineDisplayCard: View {
    @EnvironmentObject private var model: AppModel
    let offline: AppModel.OfflineDisplay

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: offline.displayClass == .builtIn ? "laptopcomputer" : "display")
                .font(.system(size: 18)).foregroundStyle(.tertiary)
            Text(offline.name).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary).lineLimit(1)
            Text("Off").font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
            Toggle("", isOn: Binding(
                get: { false },
                set: { isOn in if isOn { Task { await model.reconnectOffline(offline) } } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(model.busy)
                .help("Turn display back on")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
    }
}

/// A single full-width menu row: leading icon, title, and a trailing chevron (push), "Soon" pill
/// (not yet available), or nothing (immediate action). Hover-highlights when actionable.
private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var soon = false
    var showChevron = true
    var enabled = true
    var action: () -> Void = {}
    @State private var hovering = false

    private var active: Bool { enabled && !soon }

    var body: some View {
        Button { if active { action() } } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 14)).frame(width: 18)
                    .foregroundStyle(active ? .secondary : .tertiary)
                Text(title).font(.system(size: 13))
                    .foregroundStyle(active ? .primary : .secondary)
                Spacer()
                if soon {
                    Text("Soon").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                } else if showChevron {
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && active ? Color.secondary.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif
