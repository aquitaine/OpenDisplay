#if os(macOS)
import AppKit
import CoreGraphics
import DisplayDomain
import SwiftUI
import TopologyCore

/// The native-looking on-screen-display HUD (Batch-3 #4). A borderless, non-activating panel that
/// floats above everything, never takes focus, and is click-through — mirroring macOS's own
/// brightness/volume HUD. The *what to show* (`OSDContent`) is pure logic from DisplayDomain; this only
/// renders it and manages the show/auto-hide window. The pure `OSDPresentationPolicy` defines the
/// auto-hide duration so the timing stays consistent with the tested model.
@MainActor
final class OSDHUDController {
    private let panel: NSPanel
    private let hosting: NSHostingView<OSDHUDView>
    private var hideWorkItem: DispatchWorkItem?
    private let autoHide = OSDPresentationPolicy().autoHide

    init() {
        hosting = NSHostingView(rootView: OSDHUDView(content: OSDContent(kind: .brightness, value: 0),
                                                     style: .native))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    /// Show (or refresh) the HUD for `content` on the screen matching `cgDisplayID` (falling back to the
    /// main screen). `external` style draws nothing — the event is broadcast for a notch app instead.
    func present(_ content: OSDContent, cgDisplayID: CGDirectDisplayID?, style: OSDStyle, position: OSDPosition) {
        guard style != .external else { hide(animated: false); return }

        hosting.rootView = OSDHUDView(content: content, style: style)
        let size = OSDHUDView.size(for: style)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        if let screen = screen(for: cgDisplayID) {
            panel.setFrameOrigin(origin(for: position, size: size, in: screen.visibleFrame))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
    }

    func hide(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
    }

    private func screen(for cgDisplayID: CGDirectDisplayID?) -> NSScreen? {
        guard let cgDisplayID else { return NSScreen.main }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == cgDisplayID
        } ?? NSScreen.main
    }

    private func origin(for position: OSDPosition, size: NSSize, in frame: NSRect) -> NSPoint {
        let x = frame.midX - size.width / 2
        switch position {
        case .bottomCenter: return NSPoint(x: x, y: frame.minY + 140)
        case .topCenter: return NSPoint(x: x, y: frame.maxY - size.height - 60)
        case .center: return NSPoint(x: x, y: frame.midY - size.height / 2)
        }
    }
}

/// The HUD's SwiftUI body. `native`/`classicTahoe` render a square glyph-over-bar HUD; `minimal` is a
/// compact pill. Materials adapt to light/dark automatically (app floor is macOS 14).
struct OSDHUDView: View {
    let content: OSDContent
    let style: OSDStyle

    static func size(for style: OSDStyle) -> NSSize {
        switch style {
        case .minimal: return NSSize(width: 240, height: 48)
        default: return NSSize(width: 200, height: 200)
        }
    }

    var body: some View {
        switch style {
        case .minimal: minimalBody
        default: squareBody
        }
    }

    private var squareBody: some View {
        VStack(spacing: 18) {
            Image(systemName: content.glyph)
                .font(.system(size: 78, weight: .regular))
                .frame(height: 90)
            levelIndicator(segmentWidth: 9, segmentHeight: 9, segmentSpacing: 3)
        }
        .padding(24)
        .frame(width: 200, height: 200)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: style == .classicTahoe ? 10 : 18, style: .continuous))
    }

    private var minimalBody: some View {
        HStack(spacing: 12) {
            Image(systemName: content.glyph).font(.system(size: 18)).frame(width: 22)
            levelIndicator(segmentWidth: 8, segmentHeight: 8, segmentSpacing: 3)
        }
        .padding(.horizontal, 16)
        .frame(width: 240, height: 48)
        .background(.regularMaterial, in: Capsule())
    }

    /// The segmented level bar for brightness/volume/mute, or the switched-to input's name for
    /// `.input` — an input has no meaningful 0...1 level, so it gets a text confirmation instead.
    private func levelIndicator(segmentWidth: CGFloat, segmentHeight: CGFloat, segmentSpacing: CGFloat) -> some View {
        Group {
            if content.kind == .input {
                Text(content.label ?? "").font(.system(size: 15, weight: .medium)).lineLimit(1)
            } else {
                segments(width: segmentWidth, height: segmentHeight, spacing: segmentSpacing)
            }
        }
    }

    private func segments(width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<OSDContent.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < content.filledSegments ? Color.primary : Color.primary.opacity(0.18))
                    .frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
