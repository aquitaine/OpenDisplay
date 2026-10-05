#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

/// The "Launch at login" switch (issue #43). macOS owns the registration — `SMAppService.mainApp`,
/// the same entry the user sees under System Settings → General → Login Items — so nothing is
/// stored in OpenDisplay's own settings: the toggle reads the system's answer every time it
/// appears and whenever the app comes forward again (the user may have just flipped it there).
/// Off until the user turns it on.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Toggle(isOn: Binding(get: { Self.isOn(status) }, set: { setEnabled($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at login")
                Text(caption).font(.caption).foregroundStyle(.secondary)
                if status == .requiresApproval {
                    Button("Open Login Items Settings\u{2026}") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link).font(.caption)
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    /// `requiresApproval` counts as on: the registration exists and the user asked for it; macOS is
    /// just waiting for them to allow it, which the caption explains.
    static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    private var caption: String {
        if let failure { return "Couldn\u{2019}t change the login item: \(failure)" }
        if status == .requiresApproval {
            return "macOS is holding this until you allow OpenDisplay under System Settings \u{2192} "
                + "General \u{2192} Login Items."
        }
        return "Starts OpenDisplay when you log in, so its display rules and brightness sync are "
            + "there without you opening it."
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }

    private func refresh() {
        status = SMAppService.mainApp.status
        failure = nil
    }
}
#endif
