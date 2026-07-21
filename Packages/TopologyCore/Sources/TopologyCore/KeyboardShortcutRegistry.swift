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
    /// The DDC/CI input-source code (VCP 0x60) to switch to, e.g. 0x11 for HDMI 1.
    public var inputCode: Int
    public var binding: KeyBinding

    public init(id: String = UUID().uuidString, displayID: DisplayRecordID, inputCode: Int, binding: KeyBinding) {
        self.id = id
        self.displayID = displayID
        self.inputCode = inputCode
        self.binding = binding
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
