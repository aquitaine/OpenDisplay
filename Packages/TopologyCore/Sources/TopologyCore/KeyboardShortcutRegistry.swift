import DisplayDomain
import Foundation

/// An app action a global keyboard shortcut can trigger (Batch-2 #4). The raw value is the stable
/// serialization key.
public enum HotkeyAction: String, Hashable, Sendable, Codable, CaseIterable {
    case reconnectAll
    case cycleMainDisplay
    case brightnessUp
    case brightnessDown
    case faceLight

    public var label: String {
        switch self {
        case .reconnectAll: return "Reconnect All Displays"
        case .cycleMainDisplay: return "Cycle Main Display"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .faceLight: return "Toggle FaceLight"
        }
    }

    /// The binding shipped by default for this action (nil = unbound out of the box).
    public var defaultBinding: KeyBinding? {
        switch self {
        // ⌃⌥⌘R — the always-available Reconnect-All (recovery hierarchy step 3).
        case .reconnectAll: return KeyBinding(keyCode: 0x0F, modifiers: KeyBinding.controlOptionCommand)
        default: return nil
        }
    }
}

/// A global hotkey combo: a Carbon virtual key code plus a Carbon modifier mask. Mirrors the Carbon
/// modifier constants here so the cross-platform core doesn't import Carbon; the macOS layer passes
/// these straight to `RegisterEventHotKey`.
public struct KeyBinding: Hashable, Sendable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command: UInt32 = 0x0100   // cmdKey
    public static let shift: UInt32 = 0x0200      // shiftKey
    public static let option: UInt32 = 0x0800     // optionKey
    public static let control: UInt32 = 0x1000    // controlKey
    public static let controlOptionCommand: UInt32 = control | option | command
}

/// Which DDC/CI command an input switch sends. Most panels take MCCS VCP `0x60` from the standard
/// host source address `0x51`; many LG monitors ignore that for some inputs (notably USB-C) and
/// instead switch on LG's vendor command — VCP `0xF4` sent from source address `0x50`, with
/// LG-specific input values (see `lgAlternateInputs`). Opt-in per binding (issue #45).
public enum InputSwitchCommand: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case lgAlternate

    public var label: String {
        switch self {
        case .standard: return "Standard (VCP 0x60)"
        case .lgAlternate: return "LG alternate (VCP 0xF4)"
        }
    }

    /// The VCP feature code this command writes.
    public var vcpCode: UInt8 {
        switch self {
        case .standard: return 0x60
        case .lgAlternate: return 0xF4
        }
    }

    /// The DDC/CI host source address the write is framed with (the I2C "data address" and part of
    /// the packet checksum).
    public var sourceAddress: UInt8 {
        switch self {
        case .standard: return 0x51
        case .lgAlternate: return 0x50
        }
    }

    /// The named input values offered for this command. Standard codes follow MCCS; the LG values
    /// are the ones ddcutil and BetterDisplay document for LG's alternate command. Which value a
    /// given LG model uses for USB-C varies (0xD1 on some, 0xD2 on others), hence both entries.
    public var inputs: [(name: String, code: Int)] {
        switch self {
        case .standard: return Self.standardInputs
        case .lgAlternate: return Self.lgAlternateInputs
        }
    }

    public static let standardInputs: [(name: String, code: Int)] = [
        ("HDMI 1", 0x11), ("HDMI 2", 0x12), ("DisplayPort 1", 0x0F), ("DisplayPort 2", 0x10),
        ("USB-C", 0x1B), ("DVI", 0x03), ("VGA", 0x01),
    ]

    public static let lgAlternateInputs: [(name: String, code: Int)] = [
        ("HDMI 1", 0x90), ("HDMI 2", 0x91), ("HDMI 3", 0x92), ("HDMI 4", 0x93),
        ("DisplayPort 1", 0xD0), ("DisplayPort 2 / USB-C", 0xD1), ("USB-C", 0xD2),
    ]

    /// Human label for `code` under this command, or "Code 0xNN" if it isn't a named value.
    public func inputName(_ code: Int) -> String {
        inputs.first { $0.code == code }?.name ?? String(format: "Code 0x%02X", code)
    }
}

/// One "jump to input" hotkey binding (Lunar-parity todo 4, "Input Hotkeys") — a chord bound to
/// switching one specific display to one specific DDC input code, e.g. "⌃⌥⌘1 → Desk monitor, HDMI 2".
/// Kept apart from `HotkeyAction` because its target is user-configured data (a persistent display
/// identity plus an input code) rather than a fixed system action, so the registry holds any number
/// of these instead of the one-slot-per-action model `bindings` uses.
public struct InputSwitchBinding: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    /// The target display's persistent identity (EDID/UUID-derived `DisplayRecordID`, never a
    /// transient port/CG id), so the binding still finds the right panel after a reconnect or a
    /// dock re-plug that reorders ports.
    public var displayID: DisplayRecordID
    /// The input value to switch to, interpreted by `command` — e.g. 0x11 for HDMI 1 under the
    /// standard VCP 0x60, or 0xD2 for USB-C under LG's alternate command.
    public var inputCode: Int
    public var binding: KeyBinding
    /// Which DDC command carries `inputCode`. Absent in bindings saved before issue #45, which
    /// decode as `.standard` — exactly the behaviour they had.
    public var command: InputSwitchCommand

    public init(id: String = UUID().uuidString, displayID: DisplayRecordID, inputCode: Int,
                binding: KeyBinding, command: InputSwitchCommand = .standard) {
        self.id = id
        self.displayID = displayID
        self.inputCode = inputCode
        self.binding = binding
        self.command = command
    }

    private enum CodingKeys: String, CodingKey { case id, displayID, inputCode, binding, command }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayID = try container.decode(DisplayRecordID.self, forKey: .displayID)
        inputCode = try container.decode(Int.self, forKey: .inputCode)
        binding = try container.decode(KeyBinding.self, forKey: .binding)
        // Unknown raw values (a newer build's command) fall back to standard rather than dropping
        // the user's whole shortcut list.
        let raw = try container.decodeIfPresent(String.self, forKey: .command)
        command = raw.flatMap(InputSwitchCommand.init(rawValue:)) ?? .standard
    }
}

/// The user's global-shortcut bindings — a map from action to combo, plus any number of input-switch
/// bindings — with conflict detection and a merge-over-defaults. Pure value type (exercised by
/// `make test`); the macOS layer registers the resulting bindings via Carbon.
public struct KeyboardShortcutRegistry: Hashable, Sendable, Codable {
    public private(set) var bindings: [HotkeyAction: KeyBinding]
    /// Configured input-switch hotkeys (todo 4). Unlike `bindings`, there is no shipped default and
    /// no upper bound on how many can coexist.
    public private(set) var inputSwitchBindings: [InputSwitchBinding]

    public init(bindings: [HotkeyAction: KeyBinding] = [:], inputSwitchBindings: [InputSwitchBinding] = []) {
        self.bindings = bindings
        self.inputSwitchBindings = inputSwitchBindings
    }

    /// The shipped defaults (currently just Reconnect-All).
    public static var defaults: KeyboardShortcutRegistry {
        var b: [HotkeyAction: KeyBinding] = [:]
        for action in HotkeyAction.allCases { if let d = action.defaultBinding { b[action] = d } }
        return KeyboardShortcutRegistry(bindings: b)
    }

    public func binding(for action: HotkeyAction) -> KeyBinding? { bindings[action] }

    /// Sets (or clears, with nil) the binding for an action.
    public mutating func setBinding(_ binding: KeyBinding?, for action: HotkeyAction) {
        bindings[action] = binding
    }

    /// The action bound to a combo, if any (deterministic by action order).
    public func action(for binding: KeyBinding) -> HotkeyAction? {
        HotkeyAction.allCases.first { bindings[$0] == binding }
    }

    /// True if `binding` is already used by an action other than `excluding`.
    public func conflicts(_ binding: KeyBinding, excluding action: HotkeyAction? = nil) -> Bool {
        HotkeyAction.allCases.contains { $0 != action && bindings[$0] == binding }
    }

    /// Combos assigned to more than one action.
    public func conflictingBindings() -> [KeyBinding: [HotkeyAction]] {
        var byBinding: [KeyBinding: [HotkeyAction]] = [:]
        for action in HotkeyAction.allCases where bindings[action] != nil {
            byBinding[bindings[action]!, default: []].append(action)
        }
        return byBinding.filter { $0.value.count > 1 }
    }

    /// Adds a new input-switch binding, or replaces the existing one sharing its id.
    public mutating func addInputSwitchBinding(_ entry: InputSwitchBinding) {
        inputSwitchBindings.removeAll { $0.id == entry.id }
        inputSwitchBindings.append(entry)
    }

    /// Removes the input-switch binding with `id`, if any.
    public mutating func removeInputSwitchBinding(id: String) {
        inputSwitchBindings.removeAll { $0.id == id }
    }

    /// True if `combo` is already claimed by a fixed action or by another input-switch binding.
    /// `excludingInputSwitchID` lets an edit-in-place check exclude the entry being edited (pass nil
    /// when checking a brand-new binding).
    public func inputSwitchBindingConflicts(_ combo: KeyBinding, excludingInputSwitchID: String?) -> Bool {
        conflicts(combo) || inputSwitchBindings.contains {
            $0.id != excludingInputSwitchID && $0.binding == combo
        }
    }

    /// This registry layered over the defaults: persisted bindings win, defaults fill the gaps. There
    /// is no default input-switch binding, so those pass through unchanged.
    public func mergedWithDefaults() -> KeyboardShortcutRegistry {
        var merged = Self.defaults
        for (action, binding) in bindings { merged.bindings[action] = binding }
        merged.inputSwitchBindings = inputSwitchBindings
        return merged
    }

    private enum CodingKeys: String, CodingKey {
        case bindings
        case inputSwitchBindings
    }

    /// Decodes tolerantly across two shapes: the current `{bindings: {...}, inputSwitchBindings: [...]}`
    /// object, and the pre-todo-4 legacy shape where the WHOLE payload was the flat
    /// `{actionRawValue: KeyBinding}` map (no wrapper, no input-switch bindings). An action key a
    /// future/older build doesn't recognise is ignored rather than failing the whole load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawBindings = try container.decodeIfPresent([String: KeyBinding].self, forKey: .bindings) {
            bindings = Self.decodeBindings(rawBindings)
            inputSwitchBindings = try container.decodeIfPresent([InputSwitchBinding].self, forKey: .inputSwitchBindings) ?? []
            return
        }
        let legacyRawBindings = try decoder.singleValueContainer().decode([String: KeyBinding].self)
        bindings = Self.decodeBindings(legacyRawBindings)
        inputSwitchBindings = []
    }

    private static func decodeBindings(_ raw: [String: KeyBinding]) -> [HotkeyAction: KeyBinding] {
        var bindings: [HotkeyAction: KeyBinding] = [:]
        for (key, binding) in raw { if let action = HotkeyAction(rawValue: key) { bindings[action] = binding } }
        return bindings
    }

    public func encode(to encoder: Encoder) throws {
        var rawBindings: [String: KeyBinding] = [:]
        for (action, binding) in bindings { rawBindings[action.rawValue] = binding }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawBindings, forKey: .bindings)
        try container.encode(inputSwitchBindings, forKey: .inputSwitchBindings)
    }
}
