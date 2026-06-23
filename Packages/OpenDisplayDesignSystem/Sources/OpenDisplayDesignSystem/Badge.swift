#if os(macOS)
import SwiftUI

/// Semantic tone for badges, glyph tiles, and chips.
public enum ODTone: Sendable {
    case neutral, accent, green, orange, red

    /// The solid status color for this tone (`.neutral` has none — callers fall back to a label color).
    public var color: Color? {
        switch self {
        case .neutral: return nil
        case .accent: return ODColor.accent
        case .green: return ODColor.connected
        case .orange: return ODColor.caution
        case .red: return ODColor.danger
        }
    }
}

/// A compact status pill (`reference` `Badge`): "Main", "Offline", "Degraded", "Labs", etc. Tinted at
/// 14% for the soft variant, or filled solid for emphasis (e.g. the accent "Main" badge).
public struct ODBadge: View {
    private let text: String
    private let tone: ODTone
    private let solid: Bool

    public init(_ text: String, tone: ODTone = .neutral, solid: Bool = false) {
        self.text = text
        self.tone = tone
        self.solid = solid
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(background, in: RoundedRectangle(cornerRadius: ODRadius.badge))
    }

    private var foreground: Color {
        if solid { return ODColor.accentForeground }
        return tone.color ?? Color.secondary
    }

    private var background: Color {
        if solid { return tone.color ?? Color.secondary }
        return tone.color?.opacity(0.14) ?? ODColor.fillTertiary
    }
}

/// A small filled status dot (`reference` `Dot`), used inline where a full badge would be too heavy.
public struct ODDot: View {
    private let color: Color

    public init(_ color: Color) { self.color = color }

    public var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            ODBadge("Main", tone: .accent, solid: true)
            ODBadge("Mirrored")
            ODBadge("Offline")
        }
        HStack {
            ODBadge("Reconnecting…", tone: .accent)
            ODBadge("Degraded", tone: .orange)
            ODBadge("Healthy", tone: .green)
        }
        HStack {
            ODBadge("Labs", tone: .orange)
            ODDot(ODColor.connected)
            ODDot(ODColor.caution)
        }
    }
    .padding()
}
#endif
