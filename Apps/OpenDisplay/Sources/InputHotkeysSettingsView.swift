#if os(macOS)
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// The small fixed set of ⌃⌥⌘-digit chords offered for a new input-switch hotkey (todo 4: Lunar's
/// "Input Hotkeys"). A short pick-list, like the input-code menu already offers with
/// `AppModel.standardInputs`, rather than an open-ended key-capture recorder — that's a bigger
/// feature saved for the general hotkey-rebind follow-up this repo already has pending.
enum HotkeyDigitChords {
    /// Carbon ANSI virtual key codes for the digit row, keyed by the digit itself (1...9).
    private static let keyCodesByDigit: [Int: UInt32] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19,
    ]
    private static let fallbackDigit = 1

    static func binding(forDigit digit: Int) -> KeyBinding {
        let keyCode = keyCodesByDigit[digit] ?? keyCodesByDigit[fallbackDigit] ?? 0
        return KeyBinding(keyCode: keyCode, modifiers: KeyBinding.controlOptionCommand)
    }

    static func label(forDigit digit: Int) -> String { "\u{2303}\u{2325}\u{2318}\(digit)" }
}

/// Settings → Health & Recovery section for input-switch hotkeys: lists the configured bindings and
/// lets the user add or remove one. Reuses `AppModel.setInputSource`'s DDC path end to end — this
/// view only edits which chord targets which (display, input code) pair.
struct InputHotkeySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var isAddingBinding = false

    private var externalDisplays: [DisplayObservation] {
        model.displays.filter { $0.displayClass != .builtIn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            Text("Input hotkeys").font(.title3)
            Text("Jump a display straight to an input (HDMI, DisplayPort, USB-C\u{2026}) with a global shortcut.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(model.settings.hotkeyShortcuts.inputSwitchBindings) { entry in
                InputHotkeyRow(entry: entry)
            }

            Button {
                isAddingBinding = true
            } label: {
                Label("Add input hotkey\u{2026}", systemImage: "plus")
            }
            .disabled(externalDisplays.isEmpty)
        }
        .sheet(isPresented: $isAddingBinding) {
            AddInputHotkeySheet(isPresented: $isAddingBinding)
        }
    }
}

/// One configured binding: display name, input name, and its chord, with a remove button.
private struct InputHotkeyRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: InputSwitchBinding

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.xs) {
            ODRow(rowLabel, secondary: HotkeyDigitChords.label(forDigit: digit)) {
                Button {
                    model.removeInputSwitchHotkey(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            if model.unregisteredInputHotkeyIDs.contains(entry.id) {
                Label("macOS didn't register this shortcut. Another app may already use it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(ODColor.danger)
            }
        }
    }

    private var rowLabel: String {
        let input = entry.command.inputName(entry.inputCode)
        let suffix = entry.command == .lgAlternate ? " (LG alternate)" : ""
        return "\(displayLabel) \u{2192} \(input)\(suffix)"
    }

    private var displayLabel: String {
        model.records[entry.displayID]?.displayName ?? entry.displayID.rawValue
    }

    /// Recovers the digit this binding's key code maps to, for the secondary-line label — the chords
    /// offered are exactly the ⌃⌥⌘1...9 set `HotkeyDigitChords` mints, so every stored binding's key
    /// code round-trips back to one of them.
    private var digit: Int {
        (1...9).first { HotkeyDigitChords.binding(forDigit: $0).keyCode == entry.binding.keyCode } ?? 1
    }
}

/// Modal form for adding one input-switch hotkey: pick the display, the command (standard MCCS or
/// LG's alternate), the input value (named or custom hex), and a ⌃⌥⌘-digit chord, with a live
/// conflict check before Add enables and a Test button that sends the command once.
private struct AddInputHotkeySheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    @State private var selectedDisplayID: DisplayRecordID?
    @State private var selectedCommand: InputSwitchCommand = .standard
    /// A named input's code, or `customInputTag` when the user types their own hex value.
    @State private var selectedInputCode = InputSwitchCommand.standard.inputs.first?.code ?? 0
    @State private var customInputHex = ""
    @State private var selectedDigit = 1
    @State private var testStatus: String?
    @State private var isTesting = false

    private static let customInputTag = -1

    /// The value the binding will carry, or nil while a custom value doesn't parse as 0x00...0xFF.
    private var inputCode: Int? {
        guard selectedInputCode == Self.customInputTag else { return selectedInputCode }
        let trimmed = customInputHex.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        guard let value = Int(digits, radix: 16), (0...0xFF).contains(value) else { return nil }
        return value
    }

    private func candidate(displayID: DisplayRecordID, inputCode: Int) -> InputSwitchBinding {
        InputSwitchBinding(displayID: displayID, inputCode: inputCode, binding: candidateBinding,
                           command: selectedCommand)
    }

    private var externalDisplays: [DisplayObservation] {
        model.displays.filter { $0.displayClass != .builtIn }
    }

    private var candidateBinding: KeyBinding { HotkeyDigitChords.binding(forDigit: selectedDigit) }

    private var hasConflict: Bool {
        model.inputSwitchHotkeyConflicts(candidateBinding, excludingInputSwitchID: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.md) {
            Text("Add input hotkey").font(.headline)

            Picker("Display", selection: $selectedDisplayID) {
                ForEach(externalDisplays, id: \.recordID) { display in
                    Text(model.displayName(for: display)).tag(display.recordID as DisplayRecordID?)
                }
            }
            Picker("Command", selection: $selectedCommand) {
                ForEach(InputSwitchCommand.allCases, id: \.self) { command in
                    Text(command.label).tag(command)
                }
            }
            .onChange(of: selectedCommand) { _, command in
                selectedInputCode = command.inputs.first?.code ?? 0
                testStatus = nil
            }
            if selectedCommand == .lgAlternate {
                Text("For LG monitors that ignore the standard input command for some inputs, often USB-C. "
                     + "The USB-C value differs by model: if one doesn't work, try the other, or a custom value.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Input", selection: $selectedInputCode) {
                ForEach(selectedCommand.inputs, id: \.code) { input in
                    Text(String(format: "%@ (0x%02X)", input.name, input.code)).tag(input.code)
                }
                Divider()
                Text("Custom value\u{2026}").tag(Self.customInputTag)
            }
            .onChange(of: selectedInputCode) { _, _ in testStatus = nil }
            if selectedInputCode == Self.customInputTag {
                TextField("Hex value, e.g. 0xD2", text: $customInputHex)
                    .textFieldStyle(.roundedBorder)
                if !customInputHex.isEmpty, inputCode == nil {
                    Text("Enter a hex value from 0x00 to 0xFF.").font(.caption).foregroundStyle(ODColor.danger)
                }
            }
            HStack {
                Button("Test") { runTest() }
                    .disabled(selectedDisplayID == nil || inputCode == nil || isTesting)
                if let testStatus {
                    Text(testStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Shortcut", selection: $selectedDigit) {
                ForEach(1...9, id: \.self) { digit in
                    Text(HotkeyDigitChords.label(forDigit: digit)).tag(digit)
                }
            }
            if hasConflict {
                Text("That shortcut is already assigned.").font(.caption).foregroundStyle(ODColor.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add") { addBinding() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedDisplayID == nil || inputCode == nil || hasConflict)
            }
        }
        .padding(ODSpacing.lg)
        .frame(width: 360)
        .onAppear { selectedDisplayID = externalDisplays.first?.recordID }
    }

    private func addBinding() {
        guard let displayID = selectedDisplayID, let inputCode else { return }
        model.addInputSwitchHotkey(candidate(displayID: displayID, inputCode: inputCode))
        isPresented = false
    }

    /// Sends the command once. Reports "Sent" rather than "Switched": a DDC write has no
    /// acknowledgement, so only the monitor itself can show whether it took.
    private func runTest() {
        guard let displayID = selectedDisplayID, let inputCode else { return }
        let entry = candidate(displayID: displayID, inputCode: inputCode)
        isTesting = true
        testStatus = "Sending\u{2026}"
        Task {
            let failure = await model.testInputSwitch(entry)
            testStatus = failure.map { "Not sent: display \($0)." }
                ?? "Sent. If the monitor didn't switch, try another value."
            isTesting = false
        }
    }
}
#endif

#if os(macOS)
struct DisplayPowerHotkeySection: View {
    @EnvironmentObject private var model: AppModel

    private var targets: [String: String] {
        var result = Dictionary(uniqueKeysWithValues: model.displays.map { ($0.recordID.rawValue, model.displayName(for: $0)) })
        for offline in model.managedOffline { result[offline.recordID.rawValue] = offline.name }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display on/off shortcuts").font(.title3)
            Text("Toggle each display with Control–Option–Command–Shift and a number. The last active display stays on. Recovery: ⌃⌥⌘R.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(targets.keys.sorted(), id: \.self) { id in
                Picker(targets[id] ?? id, selection: Binding(
                    get: { model.displayPowerShortcuts[id] ?? 0 },
                    set: { model.setDisplayPowerShortcut(id, digit: $0) })) {
                    Text("None").tag(0)
                    ForEach(1...9, id: \.self) { digit in
                        Text("⌃⌥⌘⇧\(digit)").tag(digit)
                    }
                }
            }
            if let error = model.powerShortcutError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
#endif
