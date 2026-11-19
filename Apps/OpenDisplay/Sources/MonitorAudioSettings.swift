#if os(macOS)
import SwiftUI

struct MonitorAudioSettings: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: MonitorAudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Software volume for HDMI/DisplayPort audio", isOn: Binding(
                get: { controller.enabled }, set: { model.setSoftwareMonitorAudioEnabled($0) }))
            Text("Some HDMI/DisplayPort outputs do not expose an adjustable volume to macOS, so audio can play at full level. This option adds software volume control for stereo monitor audio on macOS 14.2 or later. Enable it for each listening session. The same monitor resumes after reconnect with its previous volume and mute. macOS requests System Audio Recording permission; audio is processed locally and never saved or uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            if controller.enabled {
                HStack {
                    Image(systemName: controller.level == 0 ? "speaker.slash" : "speaker.wave.2")
                    Slider(value: Binding(get: { controller.level }, set: { controller.setLevel($0) }), in: 0...1)
                    Text("\(Int(controller.level * 100))%")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                    Button("Restore normal audio") { model.setSoftwareMonitorAudioEnabled(false) }
                }
                Text("F10 mutes; F11/F12 adjust volume. Some keyboards require Fn. Allow Accessibility for these keys.")
                    .font(.caption).foregroundStyle(.secondary)
                if !controller.active {
                    Text("Processing is paused while the monitor reconnects or another sound output is selected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(controller.status).font(.caption).textSelection(.enabled)
            Toggle("Use MacBook speakers if the monitor audio output disappears", isOn: $controller.fallbackEnabled)
            Text("Keeps a working headphone, USB, or Bluetooth output selected by you. Does not change the microphone.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
#endif
