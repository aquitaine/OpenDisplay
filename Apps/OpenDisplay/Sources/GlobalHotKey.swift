#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey registered via Carbon `RegisterEventHotKey`. Carbon hotkeys do NOT
/// require the Accessibility permission an event tap would, which matters because the whole point
/// of a global Reconnect-All is to work when the menu bar is unreachable (recovery hierarchy step
/// 3, PRD §9.11 / LIF-009). The bound action runs on the main actor.
@MainActor
final class GlobalHotKey {
    // Carbon C handles, only written in init and read in deinit (no concurrent access), so the
    // unchecked isolation lets the nonisolated deinit clean them up.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private let action: () -> Void

    /// Registers the default Reconnect-All chord, ⌃⌥⌘R. Returns nil if registration fails (e.g. the
    /// chord is already claimed) so the caller can fall back to the menu-bar item.
    static func reconnectAll(action: @escaping () -> Void) -> GlobalHotKey? {
        GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            id: 1, action: action
        )
    }

    /// Registers an arbitrary system-wide chord with a unique `id` (Batch-2 #4). Returns nil if
    /// registration fails so the caller can skip that binding.
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                // Carbon delivers hotkey events on the main run loop, so this is the main actor.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                }
                return noErr
            },
            1, &eventSpec, selfPtr, &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F44_4953) /* 'ODIS' */, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
#endif
