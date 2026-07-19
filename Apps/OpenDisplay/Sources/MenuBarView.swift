#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// The menu-bar popover (primary surface), styled after the design kit's `MBDisplay`: a compact
/// per-display row that expands to the *fast, frequent* controls — one unified brightness slider,
/// volume when the panel reports it, status chips, and a few quick actions. Everything detailed
/// (resolution, colour, rotation, hardware/DDC, rename, info) lives one click away in Settings, so the
/// popover stays lean. See `Docs/InterfaceRedesign.md`.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expandedID: DisplayRecordID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            revertBanner
            ODSectionLabel("Displays")
            content
            if model.isDegraded {
                ODInlineBanner(tone: .orange, systemImage: "exclamationmark.triangle.fill",
                               title: "Some providers are unavailable",
                               message: "Open Diagnostics in Settings to see which routes are degraded.")
                    .padding(.horizontal, 2).padding(.top, 2)
            }
            ODDivider().padding(.vertical, 4)
            toolsSection
        }
        .padding(8)
        .frame(width: 320)
        .onChange(of: model.displays.count, initial: true) { _, _ in
            if expandedID == nil { expandedID = model.displays.first(where: { $0.isMain })?.recordID }
        }
    }

    /// "Keep these settings?" countdown for an arrangement-altering change (Issue 6), shown right below
    /// the icon inside this pop-out — which (via the AppKit status item) now opens on the screen the
    /// user clicked. The change also auto-reverts on its own if nothing is clicked.
    @ViewBuilder
    private var revertBanner: some View {
        if let pending = model.pendingRevert {
            VStack(alignment: .leading, spacing: 6) {
                ODInlineBanner(tone: .orange, systemImage: "clock.arrow.circlepath",
                               title: "Keep these display settings?",
                               message: "\(pending.message). Reverting in \(pending.secondsRemaining)s…")
                HStack(spacing: 8) {
                    Button("Keep") { model.confirmArrangementChange() }
                        .keyboardShortcut(.defaultAction)
                    Button("Revert now") { Task { await model.revertArrangementChange() } }
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            .padding(.bottom, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "display").font(.system(size: 18)).foregroundStyle(ODColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Displays").font(.system(size: 14, weight: .semibold))
                Text(model.statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { showSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Open Settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 15))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Quit OpenDisplay")
            .help("Quit OpenDisplay — reconnects any displays it turned off")
            Menu {
                Toggle("Keep displays awake while external connected", isOn: Binding(
                    get: { model.settings.preventDisplaySleepWithExternal },
                    set: { model.setPreventDisplaySleepWithExternal($0) }
                ))
                Toggle("Turn built-in off when an external connects", isOn: Binding(
                    get: { model.settings.autoDisconnectBuiltInOnExternal },
                    set: { model.setAutoDisconnectBuiltInOnExternal($0) }
                ))
                Divider()
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
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .scanning {
            HStack(spacing: ODSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Scanning displays…").foregroundStyle(.secondary)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } else if model.displays.isEmpty && model.managedOffline.isEmpty {
            Label("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
                .foregroundStyle(.secondary).padding(8)
        } else {
            ForEach(model.displays, id: \.recordID) { display in
                DisplayCard(display: display, expandedID: $expandedID) {
                    model.selectedDisplayID = display.recordID
                    showSettings()
                }
            }
            ForEach(model.managedOffline) { offline in
                OfflineDisplayCard(offline: offline)
            }
        }
    }

    private var toolsSection: some View {
        VStack(spacing: 2) {
            ODSectionLabel("Tools")
            MenuActionRow(title: model.busy ? "Reconnecting…" : "Reconnect all",
                          systemImage: "arrow.triangle.2.circlepath", showChevron: false,
                          enabled: !model.busy) { Task { await model.reconnectAll() } }
            MenuActionRow(title: "Displays & arrangement…", systemImage: "rectangle.3.group",
                          showChevron: true) { showSettings() }
            updatesRow
        }
    }

    /// "Check for updates" reflects the checker's live state: idle → runs a check, checking →
    /// disabled spinner text, up to date → confirmation (click re-checks), update available →
    /// version badge and a click-through to the release page.
    @ViewBuilder private var updatesRow: some View {
        switch model.updateState {
        case .idle:
            MenuActionRow(title: "Check for updates", systemImage: "arrow.down.circle",
                          showChevron: false) { Task { await model.checkForUpdates() } }
        case .checking:
            MenuActionRow(title: "Checking for updates…", systemImage: "arrow.down.circle",
                          showChevron: false, enabled: false)
        case .upToDate:
            MenuActionRow(title: "Up to date", systemImage: "checkmark.circle",
                          showChevron: false) { Task { await model.checkForUpdates() } }
        case .available(let version, _):
            MenuActionRow(title: "Update available", systemImage: "arrow.down.circle.fill",
                          badge: version, showChevron: false) { model.openUpdatePage() }
        }
    }

    /// Asks the app delegate to open Settings. The delegate owns that window (AppKit, not SwiftUI's
    /// `Settings` scene) and places it on the screen the user is looking at — opening it through the
    /// responder chain from this `NSPopover` was unreliable and often appeared to do nothing.
    private func showSettings() {
        NotificationCenter.default.post(name: .openDisplayShowSettings, object: nil)
    }
}

/// One display: a tappable header (glyph · name · sub · state badge · chevron) that expands to the
/// fast controls — unified brightness, volume (when reported), status chips, and quick actions.
private struct DisplayCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let display: DisplayObservation
    @Binding var expandedID: DisplayRecordID?
    let onOpenSettings: () -> Void
    @State private var probedHardware = false

    private var isExpanded: Bool { expandedID == display.recordID }
    private var id: DisplayRecordID { display.recordID }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isExpanded && display.isActive {
                brightnessRow
                if let volume = model.ddcControl(.volume, for: display) { volumeRow(volume) }
                chipRow
                quickActions
                MenuActionRow(title: "Display settings…", systemImage: "slider.horizontal.3",
                              showChevron: true) { onOpenSettings() }
            }
        }
        .padding(isExpanded ? 8 : 4)
        .background(isExpanded ? ODColor.cardBackground : .clear,
                    in: RoundedRectangle(cornerRadius: ODRadius.popover))
        .overlay {
            if isExpanded {
                RoundedRectangle(cornerRadius: ODRadius.popover).strokeBorder(ODColor.separator, lineWidth: 0.5)
            }
        }
        .onAppear { Task { await model.refreshBrightness(for: display) } }
        .task(id: isExpanded) {
            guard isExpanded, display.displayClass != .builtIn, !probedHardware else { return }
            await model.refreshHardwareControls(for: display)
            probedHardware = true
        }
    }

    private var header: some View {
        Button {
            if reduceMotion { expandedID = isExpanded ? nil : id }
            else { withAnimation(.easeInOut(duration: 0.15)) { expandedID = isExpanded ? nil : id } }
        } label: {
            HStack(spacing: 9) {
                ODGlyphTile(display.displayClass == .builtIn ? "laptopcomputer" : "display",
                            tone: display.isMain ? .accent : .neutral)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName(for: display))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                trailingBadge
                if display.isActive {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!display.isActive)
    }

    private var subtitle: String {
        guard display.isActive else { return "Inactive" }
        guard let mode = display.mode else { return "—" }
        return "\(mode.pointWidth) × \(mode.pointHeight) · \(Int(mode.refreshHz.rounded())) Hz"
    }

    @ViewBuilder private var trailingBadge: some View {
        if model.isBlackedOut(display) {
            ODBadge("Blacked Out", tone: .neutral)
        } else if display.isMain {
            ODBadge("Main", tone: .accent, solid: true)
        } else if display.isMirrored {
            ODBadge("Mirrored")
        } else if display.isActive {
            ODDot(ODColor.connected)
        }
    }

    private var brightnessRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            ODSliderRow(
                systemImage: "sun.min", trailingSystemImage: "sun.max",
                value: Binding(get: { Double(model.brightness[id] ?? 0.5) },
                               set: { model.setBrightness(Float($0), for: display) }),
                valueText: "\(Int(((model.brightness[id] ?? 0.5) * 100).rounded()))%",
                accessibilityLabel: "Brightness")
            if let caption = model.brightnessCaption(for: display) {
                Text(caption).font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.leading, 32).padding(.bottom, 2)
            }
        }
    }

    private func volumeRow(_ volume: Float) -> some View {
        ODSliderRow(
            systemImage: "speaker.fill", trailingSystemImage: "speaker.wave.3.fill",
            value: Binding(get: { Double(model.ddcControl(.volume, for: display) ?? volume) },
                           set: { model.setHardwareControl(.volume, Float($0), for: display) }),
            valueText: "\(Int((volume * 100).rounded()))%",
            accessibilityLabel: "Volume")
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            if let mode = display.mode {
                ODChip("\(mode.pointWidth) × \(mode.pointHeight)", systemImage: "rectangle.on.rectangle",
                       action: onOpenSettings)
                ODChip("\(Int(mode.refreshHz.rounded())) Hz", systemImage: "timer", action: onOpenSettings)
                if mode.isHiDPI { ODChip("Retina", on: true) }
            }
            if model.currentRotation(for: display) != 0 {
                ODChip("\(model.currentRotation(for: display))°", systemImage: "rotate.right",
                       action: onOpenSettings)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 2)
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            if !display.isMain {
                ODQuickAction("Set as Main", systemImage: "star", enabled: !model.busy) {
                    // Close the pop-out first so set-main relocating the menu bar can't displace it.
                    NotificationCenter.default.post(name: .openDisplayDismissMenu, object: nil)
                    Task { await model.setMain(for: display) }
                }
            }
            ODQuickAction(model.isBlackedOut(display) ? "Restore" : "Black Out",
                          systemImage: model.isBlackedOut(display) ? "sun.max.fill" : "moon.fill") {
                model.toggleBlackOut(for: display)
            }
            ODQuickAction("Turn Off", systemImage: "power", tone: .red,
                          enabled: !model.busy && model.activeDisplayCount > 1) {
                Task { await model.setDisplayActive(false, for: display) }
            }
        }
        .padding(.horizontal, 8).padding(.top, 2)
    }
}

/// A display the app has turned off: stays visible (dimmed) with a Reconnect affordance. The OS no
/// longer enumerates it, so its data comes from AppModel's managed-offline list.
private struct OfflineDisplayCard: View {
    @EnvironmentObject private var model: AppModel
    let offline: AppModel.OfflineDisplay

    var body: some View {
        HStack(spacing: 9) {
            ODGlyphTile(offline.displayClass == .builtIn ? "laptopcomputer" : "display", tone: .neutral)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(offline.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary).lineLimit(1)
                Text("Managed offline").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            Button {
                Task { await model.reconnectOffline(offline) }
            } label: {
                Label("Reconnect", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11))
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(model.busy)
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
    }
}

/// A single full-width menu row: leading icon, title, and a trailing chevron (push), "Soon" pill, or
/// nothing (immediate action). Used for the Tools section and the per-card "Display settings…" link.
private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var soon = false
    var badge: String?
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
                Text(title).font(.system(size: 13)).foregroundStyle(active ? .primary : .secondary)
                Spacer()
                if soon {
                    ODBadge("Soon")
                } else if let badge {
                    ODBadge(badge, tone: .accent, solid: true)
                } else if showChevron {
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && active ? ODColor.rowHover : .clear,
                        in: RoundedRectangle(cornerRadius: ODRadius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif
