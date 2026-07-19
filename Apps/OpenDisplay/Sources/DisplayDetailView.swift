#if os(macOS)
import AutomationSchema
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

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
                if let pending = model.pendingRevert {
                    // Timed auto-revert prompt for a change made here in Settings (Issue 6).
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
                    }
                }
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
            // Opening the detail pane is a deliberate act — if this display currently has NO working
            // hardware control, retry even negatively-cached DDC features so a monitor that just
            // recovered (power-cycle, input switch) shows its controls now. Healthy displays keep
            // their probe cache, so reopening the pane stays fast.
            model.retryDDCDiscoveryIfDead(for: display)
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
    /// Live slider position (index into `resolutions`). Applied on release (commit-on-release, per the
    /// safety note on Issue 2/#6) and re-synced to the current mode whenever the user isn't dragging.
    @State private var resolutionIndex: Double = 0
    @State private var draggingResolution = false

    /// One area-sorted stop per point-size (HiDPI preferred, then highest refresh). Shared, tested
    /// logic so the slider's index discipline stays monotonic (`ResolutionStops`).
    private var resolutions: [DisplayMode] { ResolutionStops.areaSorted(from: allModes) }

    /// The resolution stop the slider currently points at (the active stop).
    private var selectedResolution: DisplayMode? {
        let idx = Int(resolutionIndex.rounded())
        return resolutions.indices.contains(idx) ? resolutions[idx] : nil
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
                if resolutions.count > 1 {
                    HStack(spacing: 8) {
                        Slider(
                            value: $resolutionIndex,
                            in: 0...Double(resolutions.count - 1),
                            step: 1,
                            onEditingChanged: { editing in
                                draggingResolution = editing
                                if !editing { applySelectedResolution() }
                            }
                        )
                        .frame(width: 150)
                        Text(resolutionLabel)
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                    }
                } else {
                    // Single-mode display: no dead control, just the current resolution.
                    Text(display.mode.map { "\($0.pointWidth) × \($0.pointHeight)" } ?? "—")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if resolutions.count > 1, let mode = display.mode {
                // Favourite resolutions (Batch-2 #3): star the current mode + quick-recall the rest.
                ODDivider()
                ODRow("Favorites") {
                    HStack(spacing: 6) {
                        Button {
                            model.toggleFavoriteResolution(mode, for: display)
                        } label: {
                            let on = model.isFavoriteResolution(mode, for: display)
                            Image(systemName: on ? "star.fill" : "star")
                                .foregroundStyle(on ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                        .help("Pin the current resolution as a favourite")
                        ForEach(model.favoriteResolutions(among: resolutions, for: display), id: \.self) { fav in
                            if fav != mode {
                                Button("\(fav.pointWidth)×\(fav.pointHeight)") {
                                    Task { await model.setMode(fav, for: display) }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
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
        .task(id: display.recordID) {
            allModes = model.allModes(for: display)
            syncResolutionIndex()
        }
        .onChange(of: display.mode) { _, _ in syncResolutionIndex() }
    }

    /// Label for the slider's active stop — the resolution it points at, with a HiDPI hint when that
    /// stop is a Retina mode.
    private var resolutionLabel: String {
        guard let mode = selectedResolution ?? display.mode else { return "—" }
        return "\(mode.pointWidth) × \(mode.pointHeight)"
    }

    /// Applies the resolution under the slider thumb (called on drag-release, not continuously, so a
    /// drag doesn't slam the panel through every intermediate mode). No-op if it's already current.
    private func applySelectedResolution() {
        let idx = Int(resolutionIndex.rounded())
        guard resolutions.indices.contains(idx) else { return }
        let target = resolutions[idx]
        if let current = display.mode,
           current.pointWidth == target.pointWidth, current.pointHeight == target.pointHeight {
            return
        }
        Task { await model.setMode(target, for: display) }
    }

    /// Re-aligns the slider position to the display's current mode, unless the user is mid-drag.
    private func syncResolutionIndex() {
        guard !draggingResolution, let mode = display.mode,
              let idx = ResolutionStops.index(of: mode, in: resolutions) else { return }
        resolutionIndex = Double(idx)
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
                    // Offer only the preset codes the panel advertises (VCP 0x14 is a non-continuous
                    // enum); a contiguous 1...max guess offers codes the monitor silently ignores.
                    // NOTE: capabilities are only populated by an explicit read (the 0xF3 read can
                    // wedge panels, so the app never runs it automatically) — until then this takes
                    // the 1...max fallback path.
                    let codes = model.colorPresetCodes(for: display)
                    if codes.isEmpty {
                        Text(model.colorPreset[display.recordID].map { model.presetName($0) } ?? "—")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Menu(model.colorPreset[display.recordID].map { model.presetName($0) } ?? "—") {
                            ForEach(codes, id: \.self) { code in
                                Button(model.presetName(code)) { model.setColorPreset(code, for: display) }
                            }
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
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
                // A panel that answers nothing usually isn't DDC-less — its scaler's DDC channel is
                // often just stuck (a state that survives display sleep; only its own power button
                // clears it). Say so, or "unsupported" reads as a dead feature the user can't act on.
                Text("If this monitor supported hardware control before, its DDC channel may be stuck — try turning the monitor off and on with its own power button, then reopen this pane.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                    .fixedSize(horizontal: false, vertical: true)
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
            #if !PUBLIC_API_ONLY
            if let status = model.adaptiveStatusLine(for: display) {
                ODDivider()
                Text(status)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            #endif
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

    /// Gamma alone bottoms out at its floor; the overlay methods can keep going (still capped short
    /// of full black by the composer).
    private var range: ClosedRange<Double> {
        model.settings.dimmingMethod == .gamma ? 0.15...1 : 0...1
    }

    private var footnote: String {
        switch model.settings.dimmingMethod {
        case .gamma:
            return "Software gamma dim, applied on top of brightness. Works on any display, "
                + "including below the hardware minimum."
        case .overlay:
            return "A black overlay at adjustable opacity, applied on top of brightness. Works on "
                + "any display; the menu bar stays visible so you can always find your way back."
        case .combined:
            return "Gamma dim first, then a black overlay on top \u{2014} darker than either method "
                + "alone, and still never fully black."
        }
    }

    var body: some View {
        ODCard(title: "Dimming", footnote: footnote) {
            ODRow("Software dimming") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.softwareDim[display.recordID] ?? 1) },
                                          set: { model.setSoftwareDim(Float($0), for: display) }), in: range)
                        .frame(width: 160)
                    Text("\(Int(((model.softwareDim[display.recordID] ?? 1) * 100).rounded()))%")
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            ODRow("Method") {
                Picker("", selection: Binding(
                    get: { model.settings.dimmingMethod },
                    set: { model.setDimmingMethod($0) })) {
                    Text("Gamma").tag(DimmingMethod.gamma)
                    Text("Overlay").tag(DimmingMethod.overlay)
                    Text("Combined").tag(DimmingMethod.combined)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
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
