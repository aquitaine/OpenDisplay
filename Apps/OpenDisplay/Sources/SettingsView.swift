#if os(macOS)
import OpenDisplayDesignSystem
import SwiftUI

/// Placeholder settings window. The full sidebar (Displays · Arrange · Scenes · Automation ·
/// Health & Recovery · Labs) from the design kit is built out in M1–M3.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: ODSpacing.sm) {
                Text("Connected Displays").font(.title3)
                Text(model.statusText).foregroundStyle(.secondary)
                Divider()
                ForEach(model.displays, id: \.recordID) { display in
                    HStack {
                        Text(display.recordID.rawValue)
                        Spacer()
                        Text(display.isActive ? "Active" : "Managed offline")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(ODSpacing.lg)
            .tabItem { Label("Displays", systemImage: "display") }
        }
        .frame(width: 480, height: 320)
    }
}
#endif
