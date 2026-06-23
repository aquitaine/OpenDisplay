#if os(macOS)
import SwiftUI

/// An inline confirmation / recovery banner (`reference` `InlineBanner`) for potentially disruptive
/// actions — resolution change, disconnect countdown, degraded providers. A colored left rail keys the
/// tone; an optional countdown and trailing actions support "keep / revert" flows.
public struct ODInlineBanner<Actions: View>: View {
    private let tone: ODTone
    private let systemImage: String?
    private let title: String
    private let message: String?
    private let countdown: Int?
    private let actions: Actions

    public init(tone: ODTone = .accent,
                systemImage: String? = nil,
                title: String,
                message: String? = nil,
                countdown: Int? = nil,
                @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.countdown = countdown
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle().fill(rail).frame(width: 2.5).clipShape(Capsule())
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(rail).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !(actions is EmptyView) {
                    HStack(spacing: 6) { actions }.padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if let countdown {
                Text("\(countdown)s").font(.system(size: 11, weight: .medium))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(ODColor.cardBackground, in: RoundedRectangle(cornerRadius: ODRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ODRadius.card).strokeBorder(ODColor.separator, lineWidth: 0.5))
    }

    private var rail: Color { tone.color ?? ODColor.accent }
}

public extension ODInlineBanner where Actions == EmptyView {
    init(tone: ODTone = .accent, systemImage: String? = nil, title: String,
         message: String? = nil, countdown: Int? = nil) {
        self.init(tone: tone, systemImage: systemImage, title: title, message: message,
                  countdown: countdown) { EmptyView() }
    }
}

#Preview("Inline banners") {
    VStack(spacing: 10) {
        ODInlineBanner(tone: .orange, systemImage: "exclamationmark.triangle.fill",
                       title: "Some providers are unavailable",
                       message: "Hardware brightness control is degraded on this display.")
        ODInlineBanner(tone: .accent, systemImage: "rectangle.on.rectangle",
                       title: "Resolution → 2304 × 1496",
                       message: "Reverting automatically if not confirmed.", countdown: 12) {
            Button("Keep") {}
            Button("Revert") {}
        }
    }
    .padding()
    .frame(width: 320)
}
#endif
