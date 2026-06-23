#if os(macOS)
import SwiftUI

/// A labelled slider row (`reference` `MBSliderRow`) — leading icon, the track, an optional trailing
/// "max" icon, and a right-aligned value readout. Used for brightness and volume in the popover.
/// Supports both continuous live-set sliders and stepped commit-on-release sliders (resolution) via
/// `step` + `onEditingChanged`.
public struct ODSliderRow: View {
    private let systemImage: String
    private let trailingSystemImage: String?
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let valueText: String?
    private let disabled: Bool
    private let accessibilityLabel: String?
    private let onEditingChanged: (Bool) -> Void

    public init(systemImage: String,
                trailingSystemImage: String? = nil,
                value: Binding<Double>,
                in range: ClosedRange<Double> = 0...1,
                step: Double? = nil,
                valueText: String? = nil,
                disabled: Bool = false,
                accessibilityLabel: String? = nil,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.disabled = disabled
        self.accessibilityLabel = accessibilityLabel
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage).font(.system(size: 15)).foregroundStyle(.secondary)
            slider
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage).font(.system(size: 15)).foregroundStyle(.tertiary)
            }
            if let valueText {
                Text(valueText)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    @ViewBuilder private var slider: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
            } else {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
            }
        }
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

/// A compact status/toggle chip (`reference` `MBChip`): "HDR", "True Tone", "2560 × 1440", "60 Hz".
/// `on` lights it in accent; an optional `action` makes it tappable.
public struct ODChip: View {
    private let text: String
    private let systemImage: String?
    private let on: Bool
    private let tone: ODTone
    private let action: (() -> Void)?
    @State private var hovering = false

    public init(_ text: String, systemImage: String? = nil, on: Bool = false,
                tone: ODTone = .neutral, action: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.on = on
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        let chip = HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(background, in: RoundedRectangle(cornerRadius: ODRadius.control))
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            chip
        }
    }

    private var foreground: Color {
        if on { return ODColor.accent }
        if tone == .orange { return ODColor.caution }
        return Color.secondary
    }

    private var background: Color {
        if on { return ODColor.accentTint }
        if tone == .orange { return ODColor.caution.opacity(0.14) }
        return ODColor.fillTertiary.opacity(hovering && action != nil ? 1.6 : 1)
    }
}

/// One of the equal-width quick actions at the foot of an expanded display card (`reference`
/// `QuickAction`): Black Out, Sleep, Set as Main, Disconnect. Destructive actions use the red tone.
public struct ODQuickAction: View {
    private let systemImage: String
    private let label: String
    private let tone: ODTone
    private let enabled: Bool
    private let action: () -> Void
    @State private var hovering = false

    public init(_ label: String, systemImage: String, tone: ODTone = .neutral,
                enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button { if enabled { action() } } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 13))
                Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(ODColor.fillTertiary.opacity(hovering && enabled ? 1.7 : 1),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        guard enabled else { return Color.secondary.opacity(0.6) }
        return tone == .red ? ODColor.danger : Color.primary
    }
}

#Preview("Menu-bar controls") {
    VStack(alignment: .leading, spacing: 8) {
        ODSliderRow(systemImage: "sun.min", trailingSystemImage: "sun.max",
                    value: .constant(0.7), valueText: "70%")
        ODSliderRow(systemImage: "speaker.fill", trailingSystemImage: "speaker.wave.3.fill",
                    value: .constant(0.4), valueText: "40%")
        HStack(spacing: 6) {
            ODChip("HDR", systemImage: "bolt.fill", on: true)
            ODChip("True Tone")
            ODChip("2560 × 1440")
            ODChip("60 Hz")
        }
        HStack(spacing: 6) {
            ODQuickAction("Black Out", systemImage: "moon.stars") {}
            ODQuickAction("Sleep", systemImage: "moon") {}
            ODQuickAction("Disconnect", systemImage: "rectangle.portrait.slash", tone: .red) {}
        }
    }
    .padding()
    .frame(width: 306)
}
#endif
