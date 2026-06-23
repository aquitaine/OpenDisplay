#if os(macOS)
import AppKit
import SwiftUI

/// Builds an appearance-adaptive `Color` from explicit sRGB light/dark components. We resolve via
/// `NSColor`'s dynamic provider (rather than an asset catalog) because the design system ships as a
/// framework target with no catalog, and `NSColor(_: Color)` is unavailable on the macOS 13 floor.
private func odDynamic(_ light: (Double, Double, Double, Double),
                       _ dark: (Double, Double, Double, Double)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let (r, g, b, a) = isDark ? dark : light
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    })
}

/// Semantic color tokens, ported from `reference/ds/tokens/colors.css` (light `:root` + `.theme-dark`).
/// Status/accent colors differ per appearance, so each is an adaptive dynamic color. Label colors are
/// intentionally *not* here — views use SwiftUI's native `.primary`/`.secondary`/`.tertiary`/
/// `.quaternary` hierarchy, which is the adaptive equivalent of the kit's `--label-*` ramp.
public enum ODColor {
    /// System blue accent (#007AFF light / #0A84FF dark).
    public static let accent = odDynamic((0.0, 122.0/255, 1.0, 1), (10.0/255, 132.0/255, 1.0, 1))
    /// Selected-row wash behind the accent (`--accent-tint`).
    public static let accentTint = odDynamic((0.0, 122.0/255, 1.0, 0.12), (10.0/255, 132.0/255, 1.0, 0.22))
    /// Text/glyph on top of a solid accent fill.
    public static let accentForeground = Color.white

    /// Status: connected / on / success (#34C759 / #30D158).
    public static let connected = odDynamic((52.0/255, 199.0/255, 89.0/255, 1), (48.0/255, 209.0/255, 88.0/255, 1))
    /// Status: caution / unsupported (#FF9500 / #FF9F0A).
    public static let caution = odDynamic((1.0, 149.0/255, 0.0, 1), (1.0, 159.0/255, 10.0/255, 1))
    /// Status: destructive / disconnect (#FF3B30 / #FF453A).
    public static let danger = odDynamic((1.0, 59.0/255, 48.0/255, 1), (1.0, 69.0/255, 58.0/255, 1))

    // ---- Control fills (unselected), `rgba(120,120,128, a)` per appearance ----
    public static let fillPrimary = odDynamic((120.0/255, 120.0/255, 128.0/255, 0.20), (120.0/255, 120.0/255, 128.0/255, 0.36))
    public static let fillSecondary = odDynamic((120.0/255, 120.0/255, 128.0/255, 0.16), (120.0/255, 120.0/255, 128.0/255, 0.30))
    public static let fillTertiary = odDynamic((120.0/255, 120.0/255, 128.0/255, 0.12), (120.0/255, 120.0/255, 128.0/255, 0.24))
    public static let fillQuaternary = odDynamic((120.0/255, 120.0/255, 128.0/255, 0.08), (120.0/255, 120.0/255, 128.0/255, 0.18))

    /// Hairline separator (`--separator`).
    public static let separator = odDynamic((0, 0, 0, 0.10), (1, 1, 1, 0.12))
    /// Hover wash on neutral interactive rows (`--row-hover`).
    public static let rowHover = odDynamic((0, 0, 0, 0.04), (1, 1, 1, 0.06))
    /// Grouped/inset list card surface (`--card-bg`).
    public static let cardBackground = odDynamic((1, 1, 1, 1), (47.0/255, 47.0/255, 49.0/255, 1))
}

/// 4px-based spacing scale (`reference/ds/tokens/spacing.css`).
public enum ODSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// Corner radii (`reference/ds/tokens/...`): badges → controls → cards → popover → window.
public enum ODRadius {
    public static let badge: CGFloat = 4
    public static let control: CGFloat = 6
    public static let card: CGFloat = 8
    public static let popover: CGFloat = 12
    public static let window: CGFloat = 16
}

/// Type scale (`reference/ds/tokens/typography.css`), resolving to the Apple system font. Metrics
/// use tabular figures so changing numbers don't shift layout.
public enum ODFont {
    public static let caption = Font.system(size: 10)                       // dense menu-bar labels
    public static let subhead = Font.system(size: 11)                       // secondary row detail
    public static let footnote = Font.system(size: 11)
    public static let callout = Font.system(size: 12)
    public static let body = Font.system(size: 13)                          // default control + row label
    public static let headline = Font.system(size: 13, weight: .semibold)   // emphasized body
    public static let title3 = Font.system(size: 15, weight: .semibold)
    public static let title2 = Font.system(size: 17, weight: .semibold)     // group / section title
    public static let largeTitle = Font.system(size: 26, weight: .bold)
}
#endif
