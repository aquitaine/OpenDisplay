#if os(macOS)
import SwiftUI

/// Semantic color tokens from the design kit (`reference/ds/tokens/colors.css`). This is the
/// start of the SwiftUI port; the full 14-component library + light/dark asset-catalog tokens
/// land in M0/M1. Values are the light-mode constants; dark variants come with the catalog.
public enum ODColor {
    /// System blue accent (#007AFF light / #0A84FF dark).
    public static let accent = Color(red: 0.0, green: 122.0 / 255.0, blue: 1.0)
    /// Status: connected / on (#34C759).
    public static let connected = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    /// Status: caution / unsupported (#FF9500).
    public static let caution = Color(red: 1.0, green: 149.0 / 255.0, blue: 0.0)
    /// Status: destructive / disconnect (#FF3B30).
    public static let danger = Color(red: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0)
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
#endif
