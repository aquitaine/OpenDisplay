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
        ODRow(rowLabel, secondary: HotkeyDigitChords.label(forDigit: digit)) {
            Button {
                model.removeInputSwitchHotkey(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private var rowLabel: String { "\(displayLabel) \u{2192} \(model.inputName(entry.inputCode))" }

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

/// Modal form for adding one input-switch hotkey: pick the display, the input code, and a ⌃⌥⌘-digit
/// chord, with a live conflict check before the Add button enables.
private struct AddInputHotkeySheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    @State private var selectedDisplayID: DisplayRecordID?
    @State private var selectedInputCode = AppModel.standardInputs.first?.code ?? 0
    @State private var selectedDigit = 1

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
            Picker("Input", selection: $selectedInputCode) {
                ForEach(AppModel.standardInputs, id: \.code) { input in
                    Text(input.name).tag(input.code)
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
                    .disabled(selectedDisplayID == nil || hasConflict)
            }
        }
        .padding(ODSpacing.lg)
        .frame(width: 360)
        .onAppear { selectedDisplayID = externalDisplays.first?.recordID }
    }

    private func addBinding() {
        guard let displayID = selectedDisplayID else { return }
        model.addInputSwitchHotkey(InputSwitchBinding(
            displayID: displayID, inputCode: selectedInputCode, binding: candidateBinding
        ))
        isPresented = false
    }
}
#endif
