import Foundation

/// An app action a global keyboard shortcut can trigger (Batch-2 #4). The raw value is the stable
/// serialization key.
public enum HotkeyAction: String, Hashable, Sendable, Codable, CaseIterable {
    case reconnectAll
    case cycleMainDisplay
    case brightnessUp
    case brightnessDown

    public var label: String {
        switch self {
        case .reconnectAll: return "Reconnect All Displays"
        case .cycleMainDisplay: return "Cycle Main Display"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
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

/// The user's global-shortcut bindings — a map from action to combo — with conflict detection and a
/// merge-over-defaults. Pure value type (exercised by `make test`); the macOS layer registers the
/// resulting bindings via Carbon.
public struct KeyboardShortcutRegistry: Hashable, Sendable, Codable {
    public private(set) var bindings: [HotkeyAction: KeyBinding]

    public init(bindings: [HotkeyAction: KeyBinding] = [:]) {
        self.bindings = bindings
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

    /// This registry layered over the defaults: persisted bindings win, defaults fill the gaps.
    public func mergedWithDefaults() -> KeyboardShortcutRegistry {
        var merged = Self.defaults
        for (action, binding) in bindings { merged.bindings[action] = binding }
        return merged
    }

    // Serialize as a plain `{actionRawValue: KeyBinding}` JSON object, and decode tolerantly: an action
    // key a future/older build doesn't recognise is ignored rather than failing the whole load.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: KeyBinding].self)
        var bindings: [HotkeyAction: KeyBinding] = [:]
        for (key, binding) in raw { if let action = HotkeyAction(rawValue: key) { bindings[action] = binding } }
        self.bindings = bindings
    }

    public func encode(to encoder: Encoder) throws {
        var raw: [String: KeyBinding] = [:]
        for (action, binding) in bindings { raw[action.rawValue] = binding }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
