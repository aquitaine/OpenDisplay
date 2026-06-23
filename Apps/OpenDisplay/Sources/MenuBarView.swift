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
    @State private var showHardware = false
    @State private var hardwareProbed = false
    @State private var showInfo = false
    @State private var showImageAdj = false
    @State private var showDisplayMode = false
    @State private var showInput = false
    @State private var showColour = false
    @State private var showProfile = false
    @State private var showRotation = false

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
            Task { await model.refreshBrightness(for: display) }
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
        let level = model.brightness[display.recordID]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Brightness").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let level {
                    Text("\(Int((level * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Soon").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "sun.max").font(.caption).foregroundStyle(.tertiary)
                if level != nil {
                    Slider(value: Binding(
                        get: { model.brightness[display.recordID] ?? 0.5 },
                        set: { model.setBrightness($0, for: display) }), in: 0...1)
                } else {
                    Slider(value: .constant(0.5)).disabled(true).opacity(0.45)
                }
            }
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
            MenuActionRow(title: "Display mode", systemImage: "rectangle.badge.checkmark", showChevron: false) {
                withAnimation(.easeInOut(duration: 0.15)) { showDisplayMode.toggle() }
            }
            if showDisplayMode { displayModeControls }
            if !display.isMain {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 14))
                        .frame(width: 18).foregroundStyle(.secondary)
                    Text("Mirror to main display").font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { display.mirrorSourceID != nil },
                        set: { isOn in Task { await model.setMirrored(isOn, for: display) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(model.busy)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
            } else {
                MenuActionRow(title: "Mirror display", systemImage: "rectangle.on.rectangle.angled", soon: true)
            }
            MenuActionRow(title: "Move in arrangement…", systemImage: "arrow.up.left.and.arrow.down.right") {
                onOpenSettings()
            }
            MenuActionRow(title: "Screen rotation", systemImage: "rotate.right", showChevron: false) {
                withAnimation(.easeInOut(duration: 0.15)) { showRotation.toggle() }
            }
            if showRotation { rotationControls }
            if display.displayClass != .builtIn {
                MenuActionRow(title: "Colour mode", systemImage: "paintpalette", showChevron: false) {
                    withAnimation(.easeInOut(duration: 0.15)) { showColour.toggle() }
                    if showColour { Task { await model.refreshColorPreset(for: display) } }
                }
                if showColour { colourControls }
            } else {
                MenuActionRow(title: "Colour mode", systemImage: "paintpalette", soon: true)
            }
            MenuActionRow(title: "Colour profile", systemImage: "swatchpalette", showChevron: false) {
                withAnimation(.easeInOut(duration: 0.15)) { showProfile.toggle() }
                if showProfile { model.refreshColorProfile(for: display) }
            }
            if showProfile { profileControls }
            MenuActionRow(title: "Image adjustments", systemImage: "circle.righthalf.filled", showChevron: false) {
                withAnimation(.easeInOut(duration: 0.15)) { showImageAdj.toggle() }
            }
            if showImageAdj { imageAdjustments }
            if display.displayClass != .builtIn {
                MenuActionRow(title: "Hardware control", systemImage: "slider.horizontal.3", showChevron: false) {
                    withAnimation(.easeInOut(duration: 0.15)) { showHardware.toggle() }
                    if showHardware {
                        Task { await model.refreshHardwareControls(for: display); hardwareProbed = true }
                    }
                }
                if showHardware { hardwareControls }
                MenuActionRow(title: "Input source", systemImage: "cable.connector", showChevron: false) {
                    withAnimation(.easeInOut(duration: 0.15)) { showInput.toggle() }
                    if showInput { Task { await model.refreshInputSource(for: display) } }
                }
                if showInput { inputControls }
            } else {
                MenuActionRow(title: "Hardware control", systemImage: "slider.horizontal.3", soon: true)
            }
            MenuActionRow(title: "Rename & manage…", systemImage: "tag") { onOpenSettings() }
            MenuActionRow(title: "Display info", systemImage: "info.circle", showChevron: false) {
                withAnimation(.easeInOut(duration: 0.15)) { showInfo.toggle() }
            }
            if showInfo { displayInfoPanel }
        }
    }

    private var displayModeControls: some View {
        let rates = model.refreshRates(for: display)
        let hiDPIAvailable = model.hiDPIToggleAvailable(for: display)
        return VStack(alignment: .leading, spacing: 5) {
            if rates.count > 1, let current = display.mode {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                    Text("Refresh").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Menu("\(Int(current.refreshHz.rounded())) Hz") {
                        ForEach(rates, id: \.self) { hz in
                            Button("\(Int(hz.rounded())) Hz") { Task { await model.setRefresh(hz, for: display) } }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if hiDPIAvailable, let current = display.mode {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                    Text("Retina (HiDPI)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { current.isHiDPI },
                        set: { isOn in Task { await model.setHiDPI(isOn, for: display) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }
            if rates.count <= 1 && !hiDPIAvailable {
                Text("Single mode at this resolution").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var imageAdjustments: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sun.min").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                Text("Dimming").font(.caption2).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Slider(value: Binding(
                    get: { model.softwareDim[display.recordID] ?? 1 },
                    set: { model.setSoftwareDim($0, for: display) }), in: 0.15...1)
                Text("\(Int(((model.softwareDim[display.recordID] ?? 1) * 100).rounded()))%")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
            }
            Text("Software gamma dim — works on any display").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var displayInfoPanel: some View {
        VStack(spacing: 2) {
            ForEach(model.displayInfo(for: display), id: \.label) { item in
                HStack {
                    Text(item.label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.value).font(.caption2).lineLimit(1)
                }
            }
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "rotate.right").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                Text("Orientation").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.currentRotation(for: display))°").font(.caption2)
            }
            if let reason = model.rotationUnavailableReason {
                Text(reason).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Button { model.openDisplaySettings() } label: {
                Text("Open Display Settings…").font(.caption2).foregroundStyle(ODColor.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var profileControls: some View {
        let current = model.colorProfileName[display.recordID]
        let controllable = model.isColorProfileControllable(display)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "swatchpalette").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                Text("Profile").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if controllable {
                    Menu(current ?? "—") {
                        Button("Factory Default") { model.resetColorProfile(for: display) }
                        Divider()
                        ForEach(model.availableColorProfiles()) { profile in
                            Button(profile.name) { model.setColorProfile(profile, for: display) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                } else {
                    Text("Unavailable").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if controllable, let current {
                Text(current).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            } else if !controllable {
                Text("This display has no ColorSync device.").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var colourControls: some View {
        let current = model.colorPreset[display.recordID]
        let maxCode = max(model.colorPresetMax[display.recordID] ?? 5, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "paintpalette").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                Text("Preset").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Menu(current.map { model.presetName($0) } ?? "—") {
                    ForEach(1...maxCode, id: \.self) { code in
                        Button(model.presetName(code)) { model.setColorPreset(code, for: display) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Text(current == nil ? "Reading…" : "Monitor colour preset (DDC). Reversible.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var inputControls: some View {
        let current = model.inputSource[display.recordID]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "cable.connector").font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                Text("Switch to").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Menu(current.map { model.inputName($0) } ?? "—") {
                    ForEach(AppModel.standardInputs, id: \.code) { input in
                        Button(input.name) { model.setInputSource(input.code, for: display) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Text(current == nil ? "Reading…" : "Current code: \(current!). Switching is reversible.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 2)
    }

    private var hardwareControls: some View {
        VStack(spacing: 5) {
            ForEach(HardwareControl.allCases, id: \.self) { control in
                if let level = model.ddcControl(control, for: display) {
                    HStack(spacing: 6) {
                        Image(systemName: control.icon).font(.caption).foregroundStyle(.tertiary).frame(width: 15)
                        Text(control.label).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        Slider(value: Binding(
                            get: { model.ddcControl(control, for: display) ?? 0.5 },
                            set: { model.setHardwareControl(control, $0, for: display) }), in: 0...1)
                        Text("\(Int((level * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            if HardwareControl.allCases.allSatisfy({ model.ddcControl($0, for: display) == nil }) {
                Text(hardwareProbed ? "No adjustable controls reported" : "Reading…")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 26).padding(.trailing, 6).padding(.top, 2)
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
