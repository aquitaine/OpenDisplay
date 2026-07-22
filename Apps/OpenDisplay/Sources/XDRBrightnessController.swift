import AppKit
import Metal
import QuartzCore

/// Owns the tiny EDR "trigger" window XDR Brightness uses (Issue #35). Presenting one extended-
/// dynamic-range Metal frame on the XDR panel makes WindowServer raise the physical backlight
/// toward its HDR maximum (visible as `maximumExtendedDynamicRangeColorComponentValue` ramping
/// above 1) and digitally attenuate SDR content to compensate — the half of the unlock the gamma
/// boost (`XDRBrightnessPolicy`) then maps back up. The window is 8×8 px, borderless, click-
/// through, joins every Space, and is excluded from screen capture (like `DimOverlayController`'s
/// overlays); all state is process-bound, so a crash can never leave a stray window behind — and
/// the backlight itself relaxes back to SDR the moment the EDR content disappears.
@MainActor
final class XDRBrightnessController {
    private var window: NSWindow?
    private var metalLayer: CAMetalLayer?
    private var commandQueue: MTLCommandQueue?
    /// The trigger's target display, so `reconcile` can re-resolve its screen after a topology
    /// change (screens are re-created by AppKit; holding the NSScreen itself would go stale).
    private var displayID: CGDirectDisplayID?

    /// True while the trigger window is up (EDR requested; the backlight ramp follows within ~1s).
    private(set) var isEngaged = false

    /// Shows or removes the trigger window on `screen`. Idempotent — engaging while engaged just
    /// re-presents the EDR frame (cheap), so callers never need to track prior state.
    func setEngaged(_ engaged: Bool, on screen: NSScreen) {
        guard engaged else {
            disengage()
            return
        }
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        displayID = (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(triggerFrame(on: screen), display: false)
        window.orderFrontRegardless()
        isEngaged = true
        presentEDRFrame()
    }

    /// Re-fits the trigger to its display's current screen and re-presents the EDR frame — call on
    /// every topology change (mirrors `dimOverlay.reconcile()`). A reconfiguration can move the
    /// screen out from under the window or drop the presented drawable, silently ending the EDR
    /// request and letting the backlight sag back to SDR while the gamma boost stays applied.
    /// If the display is gone, the trigger disengages (the model also clears its boost).
    func reconcile(screens: [NSScreen]) {
        guard isEngaged, let displayID else { return }
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = screens.first(where: {
            ($0.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        }) else {
            disengage()
            return
        }
        setEngaged(true, on: screen)
    }

    /// Tears the trigger window down; the backlight relaxes back to SDR on its own. The screen-
    /// free spelling of `setEngaged(false, on:)`, for callers whose display may already be gone.
    func disengage() {
        window?.orderOut(nil)
        window = nil
        metalLayer = nil
        commandQueue = nil
        displayID = nil
        isEngaged = false
    }

    /// The 8×8 pt trigger rect in the screen's top-left corner (AppKit coordinates are bottom-left
    /// origin, so top-left is at `maxY`).
    private func triggerFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.maxY - 8, width: 8, height: 8)
    }

    /// Builds the borderless trigger window hosting the EDR Metal layer. The layer asks for
    /// extended-range content in a half-float extended-linear colorspace — the combination that
    /// makes WindowServer treat pixel values above 1.0 as genuine EDR and engage the backlight.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 8, height: 8),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.animationBehavior = .none
        window.setAccessibilityElement(false)

        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.wantsExtendedDynamicRangeContent = true
        layer.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        metalLayer = layer
        commandQueue = layer.device?.makeCommandQueue()

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        return window
    }

    /// Presents one EDR clear frame (pixel value 8.0 — far above SDR white) into the layer. A
    /// single presented frame is enough: WindowServer keeps the backlight raised for as long as
    /// the drawable stays on screen, no per-frame rendering needed.
    private func presentEDRFrame() {
        guard let layer = metalLayer, let queue = commandQueue,
              let drawable = layer.nextDrawable() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 8, green: 8, blue: 8, alpha: 1)
        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
