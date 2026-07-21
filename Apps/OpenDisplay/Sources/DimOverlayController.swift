import AppKit

/// Owns the click-through overlay windows the overlay/combined dimming methods (and FaceLight) use —
/// one per display carrying an overlay. Windows are borderless, ignore the mouse, join every Space,
/// sit just below the status bar (so the menu bar and this app's popover stay reachable at any dim
/// level — the escape hatch is never dimmed away), and are excluded from screen capture so
/// screenshots come out clean. All state is process-bound: every overlay vanishes the instant the
/// app exits, so unlike a gamma dim there is nothing to restore on quit.
@MainActor
final class DimOverlayController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    /// Applies `alpha` (0...1, where 0 removes the overlay) to the display's overlay window, tinted
    /// with `color` (default opaque black, for the dimming methods; FaceLight passes a warm-white
    /// tint instead), creating the window on first use. No-ops if the display has no NSScreen
    /// (offline / mid-reconfig).
    func setAlpha(_ alpha: Float, color: NSColor = .black, for displayID: CGDirectDisplayID) {
        guard alpha > 0.001 else {
            remove(for: displayID)
            return
        }
        guard let screen = Self.screen(for: displayID) else { return }
        let window = windows[displayID] ?? makeWindow(on: screen)
        windows[displayID] = window
        window.setFrame(screen.frame, display: false)
        window.backgroundColor = color
        window.alphaValue = CGFloat(alpha)
        window.orderFrontRegardless()
    }

    func remove(for displayID: CGDirectDisplayID) {
        windows.removeValue(forKey: displayID)?.orderOut(nil)
    }

    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    /// Drops overlays for displays that no longer exist and re-fits the rest to their screen's
    /// current frame. Call after any topology change — a resolution switch or rearrangement moves
    /// the screen out from under the window.
    func reconcile() {
        for (displayID, window) in windows {
            if let screen = Self.screen(for: displayID) {
                window.setFrame(screen.frame, display: false)
            } else {
                remove(for: displayID)
            }
        }
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Below statusBar: normal windows and the Dock dim; the menu bar and our popover do not.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.animationBehavior = .none
        window.setAccessibilityElement(false)
        return window
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == displayID
        }
    }
}
