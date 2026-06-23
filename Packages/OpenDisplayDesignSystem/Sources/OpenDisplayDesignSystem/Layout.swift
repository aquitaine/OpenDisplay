#if os(macOS)
import SwiftUI

/// A 28×28 rounded tile holding an SF Symbol (`reference` `GlyphTile`) — the leading identity glyph on
/// every display row. Accent tone fills solid; status tones tint softly; neutral uses a fill wash.
public struct ODGlyphTile: View {
    private let systemImage: String
    private let tone: ODTone
    private let glyphSize: CGFloat

    public init(_ systemImage: String, tone: ODTone = .neutral, glyphSize: CGFloat = 17) {
        self.systemImage = systemImage
        self.tone = tone
        self.glyphSize = glyphSize
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: glyphSize))
            .foregroundStyle(foreground)
            .frame(width: 28, height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
    }

    private var foreground: Color {
        switch tone {
        case .accent: return ODColor.accentForeground
        case .neutral: return Color.secondary
        default: return tone.color ?? Color.secondary
        }
    }

    private var background: Color {
        switch tone {
        case .accent: return ODColor.accent
        case .neutral: return ODColor.fillSecondary
        default: return tone.color?.opacity(0.16) ?? ODColor.fillSecondary
        }
    }
}

/// An uppercase section header (`reference` `SectionLabel`): "DISPLAYS", "TOOLS", with an optional
/// trailing accessory (e.g. a count or a small button).
public struct ODSectionLabel<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

public extension ODSectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title, trailing: { EmptyView() }) }
}

/// A hairline separator (`reference` `Divider`), inset from the left to clear leading glyphs.
public struct ODDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = 11) { self.inset = inset }

    public var body: some View {
        Rectangle()
            .fill(ODColor.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// A grouped "inset" card (`reference` `Card`) — the rounded surface that holds a list of setting
/// rows, with an optional group title above and footnote below.
public struct ODCard<Content: View>: View {
    private let title: String?
    private let footnote: String?
    private let padded: Bool
    private let content: Content

    public init(title: String? = nil, footnote: String? = nil, padded: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.padded = padded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(padded ? 12 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ODColor.cardBackground, in: RoundedRectangle(cornerRadius: ODRadius.card))
                .overlay(RoundedRectangle(cornerRadius: ODRadius.card).strokeBorder(ODColor.separator, lineWidth: 0.5))
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
        }
    }
}

/// A settings row (`reference` `Row`): leading accessory, a label (+ optional secondary line), and a
/// trailing control. Hoverable + selectable when given an `action`.
public struct ODRow<Leading: View, Trailing: View>: View {
    private let label: String
    private let secondary: String?
    private let selected: Bool
    private let leading: Leading
    private let trailing: Trailing
    private let action: (() -> Void)?
    @State private var hovering = false

    public init(_ label: String, secondary: String? = nil, selected: Bool = false,
                action: (() -> Void)? = nil,
                @ViewBuilder leading: () -> Leading,
                @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.secondary = secondary
        self.selected = selected
        self.action = action
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        let row = HStack(spacing: 9) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
                if let secondary {
                    Text(secondary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: ODRadius.card))
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            row
        }
    }

    private var background: Color {
        if selected { return ODColor.accentTint }
        if action != nil && hovering { return ODColor.rowHover }
        return .clear
    }
}

// Convenience initializers for the common row shapes (no leading glyph, or no trailing control).
public extension ODRow where Leading == EmptyView {
    init(_ label: String, secondary: String? = nil, selected: Bool = false,
         action: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(label, secondary: secondary, selected: selected, action: action,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

// Note: there is intentionally no single-trailing-closure "leading only" convenience — it would be
// ambiguous with the trailing-only init above. A leading glyph with no trailing control uses the main
// init with an explicit `trailing: { EmptyView() }`.

public extension ODRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ label: String, secondary: String? = nil, selected: Bool = false, action: (() -> Void)? = nil) {
        self.init(label, secondary: secondary, selected: selected, action: action,
                  leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

#Preview("Layout") {
    VStack(alignment: .leading, spacing: 12) {
        ODSectionLabel("Displays") { ODBadge("3") }
        HStack { ODGlyphTile("display", tone: .accent); ODGlyphTile("laptopcomputer"); ODGlyphTile("display.trianglebadge.exclamationmark", tone: .orange) }
        ODCard(title: "Resolution", footnote: "Scaled resolutions use HiDPI rendering.") {
            ODRow("Resolution") { Text("2560 × 1440").font(.system(size: 11)).foregroundStyle(.secondary) }
            ODDivider()
            ODRow("Refresh rate") { Text("60 Hz").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        ODRow("Studio Display", secondary: "5120 × 2880 · 60 Hz", action: {}) {
            ODGlyphTile("display", tone: .accent)
        } trailing: {
            ODBadge("Main", tone: .accent, solid: true)
        }
    }
    .padding()
    .frame(width: 360)
}
#endif
