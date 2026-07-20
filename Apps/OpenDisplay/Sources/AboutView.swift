#if os(macOS)
import AppKit
import OpenDisplayDesignSystem
import SwiftUI

/// Custom About window, replacing `orderFrontStandardAboutPanel`. The standard panel only shows
/// the icon + version; this one adds what people actually come for — the running version (selectable
/// for bug reports), an update check, and links to the project. Accessibility: semantic fonts (respect
/// the user's text-size setting), real `Link` controls (focusable, VoiceOver-labelled), and the
/// decorative icon hidden from assistive tech.
struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    private static let repo = "https://github.com/aquitaine/OpenDisplay"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: ODSpacing.sm) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("OpenDisplay")
                .font(.title2.weight(.semibold))
            Text("Free, open-source display control for macOS.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version \(version) (build \(build))")
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
                .accessibilityLabel("Version \(version), build \(build)")
                .padding(.top, 2)
            updateStatus

            Divider().padding(.vertical, ODSpacing.xs)

            VStack(alignment: .leading, spacing: ODSpacing.sm) {
                aboutLink("Website", systemImage: "globe", url: Self.repo)
                aboutLink("Release notes", systemImage: "doc.text", url: "\(Self.repo)/releases")
                aboutLink("Report an issue", systemImage: "ladybug", url: "\(Self.repo)/issues/new")
                aboutLink("License (GPL-3.0)", systemImage: "checkmark.seal",
                          url: "\(Self.repo)/blob/main/LICENSE")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ODSpacing.lg)

            Text("© 2026 OpenDisplay contributors")
                .font(.footnote).foregroundStyle(.tertiary)
                .padding(.top, ODSpacing.xs)
        }
        .padding(.vertical, ODSpacing.xl)
        .padding(.horizontal, ODSpacing.xl)
        .frame(width: 300)
    }

    /// Mirrors the menu's update row: idle → button, checking → progress, result → outcome text
    /// (with a click-through to the release page when one is available).
    @ViewBuilder private var updateStatus: some View {
        switch model.updateState {
        case .idle:
            Button("Check for Updates…") { Task { await model.checkForUpdates() } }
                .controlSize(.small)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").font(.callout).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(.secondary)
        case .available(let version, _):
            Button {
                model.openUpdatePage()
            } label: {
                Label("Update available: \(version)", systemImage: "arrow.down.circle.fill")
            }
            .controlSize(.small)
            .accessibilityHint("Opens the release page in your browser")
        }
    }

    private func aboutLink(_ title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label {
                Text(title).font(.callout)
            } icon: {
                Image(systemName: systemImage).frame(width: 18)
            }
        }
        .foregroundStyle(ODColor.accent)
        .accessibilityHint("Opens in your browser")
    }
}
#endif
