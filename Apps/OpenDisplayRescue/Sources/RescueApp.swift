#if os(macOS)
import CoreGraphicsProvider
import DisplayDomain
import Foundation
import SwiftUI
import TopologyCore

/// The independent rescue utility (PRD LIF-011, DIA-010, D-004). It reads the last-known-safe
/// checkpoint the main app persisted to Application Support — a single well-known JSON file — and
/// can restore the recorded arrangement using only public Core Graphics APIs, so it works even
/// when the main app is unavailable. Minimal-dependency by design.
@main
struct OpenDisplayRescueApp: App {
    var body: some Scene {
        WindowGroup("OpenDisplay Rescue") {
            RescueView()
        }
        .defaultSize(width: 480, height: 360)
    }
}

@MainActor
final class RescueModel: ObservableObject {
    @Published private(set) var status = "Reading last-known-safe checkpoint…"
    @Published private(set) var displays: [DisplayObservation] = []
    @Published private(set) var capturedAt: Date?
    @Published private(set) var busy = false

    private let store: (any CheckpointStoring)?
    private let lifecycle = CoreGraphicsProvider()
    private var checkpoint: Checkpoint?

    init() {
        store = (try? DiskCheckpointStore.defaultDirectory()).map(DiskCheckpointStore.init(directory:))
        Task { await load() }
    }

    func load() async {
        guard let store else {
            status = "Couldn't locate the checkpoint store."
            return
        }
        guard let checkpoint = await store.latest() else {
            status = "No checkpoint found yet — launch OpenDisplay once to record a baseline."
            return
        }
        self.checkpoint = checkpoint
        displays = checkpoint.observations.sorted { $0.recordID.rawValue < $1.recordID.rawValue }
        capturedAt = checkpoint.createdAt
        status = "Loaded the last-known-safe checkpoint. This runs independently of the main app."
    }

    /// Restores the recorded arrangement with the public mirroring provider (un-mirrors the
    /// displays the checkpoint recorded as active). Idempotent and hardware-safe.
    func reconnectAll() async {
        guard let checkpoint else { return }
        busy = true
        defer { busy = false }
        do {
            try await lifecycle.recover(to: checkpoint)
            status = "Reconnect All complete — restored the recorded arrangement."
        } catch {
            status = "Reconnect All failed: \(error)"
        }
    }
}

struct RescueView: View {
    @StateObject private var model = RescueModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenDisplay Rescue").font(.title3).bold()
                    if let capturedAt = model.capturedAt {
                        Text("Checkpoint captured \(capturedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            if model.displays.isEmpty {
                Text(model.status).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.displays, id: \.recordID) { display in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(display.isActive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(display.recordID.rawValue).font(.system(.body, design: .monospaced))
                        if display.isMain { Text("Main").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        Text(display.isActive ? "Active" : "Offline")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reconnect All") { Task { await model.reconnectAll() } }
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy || model.displays.isEmpty)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
