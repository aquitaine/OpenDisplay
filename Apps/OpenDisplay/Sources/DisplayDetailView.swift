#if os(macOS)
import AutomationSchema
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI

/// The per-display detail pane (Settings → Displays). This is where everything that used to crowd the
/// menu-bar card now lives: resolution & refresh, appearance (rotation/colour), hardware controls,
/// input, "use as", identity, and read-only info — grouped into System-Settings-style cards. The menu
/// bar deep-links here via "Display settings…". See `Docs/InterfaceRedesign.md`.
struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ResolutionCard(display: display)
                AppearanceCard(display: display)
                if display.displayClass != .builtIn { ControlsCard(display: display) }
                DimmingCard(display: display)
                UseAsCard(display: display)
                IdentityCard(display: display)
                InformationCard(display: display)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: display.recordID) {
            await model.refreshBrightness(for: display)
            await model.refreshColorProfile(for: display)
            if display.displayClass != .builtIn {
                await model.refreshHardwareControls(for: display)
                await model.refreshColorPreset(for: display)
                await model.refreshInputSource(for: display)
            }
        }
    }
}

// MARK: - Resolution

private struct ResolutionCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    /// Full mode list, enumerated once per display (off the per-render path) and filtered locally for
    /// the resolution list, refresh rates, and HiDPI toggle — avoids three CGDisplayCopyAllDisplayModes
    /// enumerations on every body evaluation. Filters use the *current* display.mode, so they stay
    /// correct across resolution switches without re-enumerating.
    @State private var allModes: [DisplayMode] = []

    /// One entry per point-size (HiDPI preferred, then highest refresh), area-sorted.
    private var resolutions: [DisplayMode] {
        var best: [String: DisplayMode] = [:]
        for mode in allModes {
            let key = "\(mode.pointWidth)x\(mode.pointHeight)"
            let rank = (mode.isHiDPI ? 1 : 0, mode.refreshHz)
            if let existing = best[key] {
                if rank > (existing.isHiDPI ? 1 : 0, existing.refreshHz) { best[key] = mode }
            } else {
                best[key] = mode
            }
        }
        return best.values.sorted { $0.pointWidth * $0.pointHeight < $1.pointWidth * $1.pointHeight }
    }

    /// Refresh rates at the current resolution (same point-size + HiDPI), descending.
    private var rates: [Double] {
        guard let current = display.mode else { return [] }
        let hz = allModes
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight && $0.isHiDPI == current.isHiDPI }
            .map { ($0.refreshHz * 10).rounded() / 10 }
        return Array(Set(hz)).sorted(by: >)
    }

    /// True when the current resolution offers both a HiDPI and a non-HiDPI variant.
    private var hiDPIAvailable: Bool {
        guard let current = display.mode else { return false }
        let here = allModes.filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
        return here.contains(where: { $0.isHiDPI }) && here.contains(where: { !$0.isHiDPI })
    }

    var body: some View {
        ODCard(title: "Resolution",
               footnote: "Scaled resolutions use HiDPI (Retina) rendering for crisper text.") {
            ODRow("Resolution") {
                if resolutions.count > 1, let mode = display.mode {
                    Menu("\(mode.pointWidth) × \(mode.pointHeight)") {
                        ForEach(resolutions, id: \.self) { m in
                            Button("\(m.pointWidth) × \(m.pointHeight)") {
                                Task { await model.setMode(m, for: display) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                } else {
                    Text(display.mode.map { "\($0.pointWidth) × \($0.pointHeight)" } ?? "—")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if rates.count > 1, let mode = display.mode {
                ODDivider()
                ODRow("Refresh rate") {
                    Menu("\(Int(mode.refreshHz.rounded())) Hz") {
                        ForEach(rates, id: \.self) { hz in
                            Button("\(Int(hz.rounded())) Hz") { Task { await model.setRefresh(hz, for: display) } }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if hiDPIAvailable, let mode = display.mode {
                ODDivider()
                ODRow("Retina (HiDPI)") {
                    Toggle("", isOn: Binding(get: { mode.isHiDPI },
                                             set: { on in Task { await model.setHiDPI(on, for: display) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        .task(id: display.recordID) { allModes = model.allModes(for: display) }
    }
}

// MARK: - Appearance (rotation + colour)

private struct AppearanceCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Appearance") {
            ODRow("Rotation") {
                if model.rotationWritable {
                    HStack(spacing: 6) {
                        ODBadge("Experimental", tone: .orange)
                        Menu("\(model.currentRotation(for: display))°") {
                            ForEach([0, 90, 180, 270], id: \.self) { deg in
                                Button("\(deg)°") { Task { await model.setRotation(deg, for: display) } }
                            }
                        }
                        .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                    }
                } else {
                    Text("\(model.currentRotation(for: display))°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if display.displayClass != .builtIn {
                ODDivider()
                ODRow("Colour mode") {
                    Menu(model.colorPreset[display.recordID].map { model.presetName($0) } ?? "—") {
                        let maxCode = max(model.colorPresetMax[display.recordID] ?? 5, 1)
                        ForEach(1...maxCode, id: \.self) { code in
                            Button(model.presetName(code)) { model.setColorPreset(code, for: display) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            ODDivider()
            ODRow("Colour profile") {
                if model.colorProfileControllable[display.recordID] == true {
                    Menu(model.colorProfileName[display.recordID] ?? "—") {
                        Button("Factory Default") { Task { await model.resetColorProfile(for: display) } }
                        Divider()
                        ForEach(model.availableColorProfilesCache) { profile in
                            Button(profile.name) { Task { await model.setColorProfile(profile, for: display) } }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                } else {
                    Text("Unavailable").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        if let reason = model.rotationUnavailableReason {
            Text(reason).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10)
        }
    }
}

// MARK: - Hardware controls (DDC, external only)

private struct ControlsCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Controls",
               footnote: "Hardware controls sent over DDC/CI. Availability depends on the monitor.") {
            let controls = HardwareControl.allCases.filter { model.ddcControl($0, for: display) != nil }
            if controls.isEmpty {
                ODRow("No adjustable hardware controls reported") {}
            } else {
                ForEach(Array(controls.enumerated()), id: \.element) { index, control in
                    if index > 0 { ODDivider() }
                    ODRow(control.label) {
                        sliderWithReadout(level: model.ddcControl(control, for: display) ?? 0.5) { value in
                            model.setHardwareControl(control, value, for: display)
                        }
                    }
                }
            }
            ODDivider()
            ODRow("Input source") {
                Menu(model.inputSource[display.recordID].map { model.inputName($0) } ?? "—") {
                    ForEach(AppModel.standardInputs, id: \.code) { input in
                        Button(input.name) { model.setInputSource(input.code, for: display) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            ODDivider()
            ODRow("Power", secondary: "Some displays can't wake over DDC once off") {
                Menu("Set…") {
                    ForEach(DDCPowerMode.allCases, id: \.self) { mode in
                        Button(mode.label) { model.setPowerMode(mode, for: display) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    private func sliderWithReadout(level: Float, set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(level) }, set: { set(Float($0)) }), in: 0...1)
                .frame(width: 160)
            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

// MARK: - Software dimming (any display)

private struct DimmingCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Dimming",
               footnote: "Software gamma dim, applied on top of brightness. Works on any display, "
               + "including below the hardware minimum.") {
            ODRow("Software dimming") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.softwareDim[display.recordID] ?? 1) },
                                          set: { model.setSoftwareDim(Float($0), for: display) }), in: 0.15...1)
                        .frame(width: 160)
                    Text("\(Int(((model.softwareDim[display.recordID] ?? 1) * 100).rounded()))%")
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Use as

private struct UseAsCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Use as") {
            ODRow("Use as main display", secondary: "Menu bar and Dock appear here") {
                Toggle("", isOn: Binding(get: { display.isMain },
                                         set: { on in if on { Task { await model.setMain(for: display) } } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(display.isMain || model.busy)
            }
            if !display.isMain {
                ODDivider()
                ODRow("Mirror to main display") {
                    Toggle("", isOn: Binding(get: { display.isMirrored },
                                             set: { on in Task { await model.setMirrored(on, for: display) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.busy)
                }
            }
            ODDivider()
            ODRow("Turn display off", secondary: "Logical disconnect — reconnectable") {
                Button("Turn Off", role: .destructive) {
                    Task { await model.setDisplayActive(false, for: display) }
                }
                .controlSize(.small)
                .disabled(model.busy || model.activeDisplayCount <= 1)
            }
        }
    }
}

// MARK: - Identity (rename)

private struct IdentityCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    @State private var alias = ""

    var body: some View {
        ODCard(title: "Name") {
            ODRow("Display name") {
                TextField(model.displayName(for: display), text: $alias)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit { Task { await model.setAlias(alias, for: display) } }
            }
        }
        .onAppear { alias = model.records[display.recordID]?.alias ?? "" }
    }
}

// MARK: - Information (read-only)

private struct InformationCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Information") {
            let info = model.displayInfo(for: display)
            ForEach(Array(info.enumerated()), id: \.element.label) { index, item in
                if index > 0 { ODDivider() }
                ODRow(item.label) {
                    Text(item.value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
#endif
