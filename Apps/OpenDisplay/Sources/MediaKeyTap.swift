#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import TopologyCore

/// Captures the hardware brightness/volume media keys and routes them to OpenDisplay (Batch-3 #3).
///
/// macOS delivers these as `systemDefined` (`NX_SYSDEFINED`) events, which a Carbon hotkey can't see —
/// so this uses a `CGEventTap`. An *active* tap (not listen-only) is required so OpenDisplay can
/// **consume** a handled key, suppressing the system's own HUD (we draw our own via `OSDHUDController`).
/// That capability needs the **Accessibility** permission; `start()` returns false when it isn't
/// granted, leaving the keys to behave normally. The decode→action mapping is the pure, unit-tested
/// `MediaKeyAction`; this is only the OS plumbing.
@MainActor
final class MediaKeyTap {
    /// Handle a key. Return `true` if OpenDisplay acted on it (the event is then swallowed), `false` to
    /// let it pass through to macOS (e.g. a volume key with no DDC-audio-capable target). Invoked on the
    /// main actor (the tap runs on the main run loop), so it can touch `AppModel`.
    private let handler: @MainActor (MediaKeyAction, _ fineStep: Bool) -> Bool

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping @MainActor (MediaKeyAction, _ fineStep: Bool) -> Bool) {
        self.handler = handler
    }

    /// Whether the process currently holds the Accessibility (TCC) grant the tap needs.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Show the system Accessibility prompt (the one-time grant request). Called only when the user
    /// turns the feature on, so a user who never enables it is never prompted.
    static func promptForAccessibility() {
        // Use the documented constant's literal value rather than the imported global `var`
        // `kAXTrustedCheckOptionPrompt`, which Swift 6 flags as not concurrency-safe to reference.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Create + enable the tap. Returns false (a no-op) when Accessibility isn't granted or the tap
    /// can't be created — the keys then reach macOS unchanged.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard Self.isAccessibilityTrusted else { return false }

        let mask = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: mediaKeyTapCallback, userInfo: refcon
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// Re-arm the tap if the system disabled it (timeout / user input). Called from the C callback.
    func reEnableIfNeeded() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Dispatch a decoded media key to the handler; returns whether it was consumed.
    func dispatch(_ action: MediaKeyAction, fineStep: Bool) -> Bool {
        handler(action, fineStep)
    }

    /// Decode a systemDefined CGEvent into a media-key action (+ fine-step modifier), or nil if it isn't
    /// a media-key *press* we care about. `nonisolated` + pure of actor state — returns only Sendable
    /// values, so the C callback can do this outside the main-actor hop (CGEvent isn't Sendable).
    nonisolated static func decode(_ cgEvent: CGEvent) -> (action: MediaKeyAction, fineStep: Bool)? {
        guard let nsEvent = NSEvent(cgEvent: cgEvent), nsEvent.subtype.rawValue == 8 else { return nil }
        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF_0000) >> 16)
        let keyFlags = data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard isKeyDown, let action = MediaKeyAction.from(nxKeyType: keyCode) else { return nil }
        let fineStep = nsEvent.modifierFlags.contains(.shift) && nsEvent.modifierFlags.contains(.option)
        return (action, fineStep)
    }
}

/// Top-level C callback (must not capture) for the media-key event tap. Recovers the owning
/// `MediaKeyTap` from `refcon` and consumes the event when handled. The tap runs on the main run loop,
/// so it's safe to hop onto the main actor; only Sendable decoded values cross that hop (not the
/// non-Sendable `CGEvent`).
private func mediaKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reEnableIfNeeded() }
        return Unmanaged.passUnretained(event)
    }

    guard let decoded = MediaKeyTap.decode(event) else { return Unmanaged.passUnretained(event) }
    let consumed = MainActor.assumeIsolated { tap.dispatch(decoded.action, fineStep: decoded.fineStep) }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
#endif
