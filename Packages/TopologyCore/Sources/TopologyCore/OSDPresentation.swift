import DisplayDomain
import Foundation

/// Visual style for the OSD HUD (Batch-3 #5 exposes this; the renderer reads it).
public enum OSDStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// macOS-like segmented HUD (default).
    case native
    /// Compact pill with glyph + bar.
    case minimal
    /// Pre-Tahoe classic HUD look.
    case classicTahoe
    /// Don't draw OpenDisplay's own HUD — only broadcast events (Batch-3 #6) for an external/notch HUD.
    case external
}

/// Where the HUD appears on the target display.
public enum OSDPosition: String, Hashable, Sendable, Codable, CaseIterable {
    case bottomCenter
    case topCenter
    case center
}

/// Decides when to show / refresh / hide the OSD HUD (Batch-3 #2). Pure timing logic (exercised by
/// `make test`); the macOS layer owns the actual window + timer. Rapid changes coalesce: each event
/// pushes the auto-hide deadline forward, so a key-repeat or a slider drag is one continuously-visible
/// HUD rather than a flicker stack.
public struct OSDPresentationPolicy: Sendable {
    /// Seconds the HUD stays up after the last change.
    public var autoHide: TimeInterval
    /// When true, an event identical to what's already shown is ignored rather than re-shown.
    public var suppressUnchanged: Bool

    public init(autoHide: TimeInterval = 1.2, suppressUnchanged: Bool = false) {
        self.autoHide = max(0, autoHide)
        self.suppressUnchanged = suppressUnchanged
    }

    public enum Decision: Hashable, Sendable {
        /// Show (or update) the HUD with `content`, scheduling it to hide at `hideAt`.
        case show(OSDContent, hideAt: Date)
        /// Do nothing (a suppressed no-op).
        case ignore
    }

    /// Decide what to do for a new `event` given the currently-shown `previous` content.
    public func decide(event: OSDContent, previous: OSDContent?, now: Date) -> Decision {
        if suppressUnchanged, let previous, previous == event { return .ignore }
        return .show(event, hideAt: now.addingTimeInterval(autoHide))
    }

    /// Whether a HUD scheduled to hide at `hideAt` should now be hidden.
    public func shouldHide(now: Date, hideAt: Date) -> Bool {
        now >= hideAt
    }
}
