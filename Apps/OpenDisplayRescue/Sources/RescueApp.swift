#if os(macOS)
import CoreGraphicsProvider
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation
import SwiftUI
import TopologyCore

/// The independent rescue utility (PRD LIF-011, DIA-010, D-004). It reads the last-known-safe
/// checkpoint the main app persisted to Application Support — a single well-known JSON file — and
/// restores the recorded arrangement even when the main app is unavailable. Recovery runs BOTH
/// mechanisms best-effort: a SkyLight re-enable transaction (undoes a private logical disconnect)
/// and a public Core Graphics un-mirror (undoes the mirroring fallback). Minimal-dependency.
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
    private let observer = CoreGraphicsProvider()   // also the public un-mirror LifecycleProvider
    private let reEnable = ExperimentalLifecycleProvider()  // private SkyLight re-enable
    private var checkpoint: Checkpoint?

    init() {
        store = (try? DiskCheckpointStore.defaultDirectory()).map(DiskCheckpointStore.init(directory:))
        Task {
            await load()
            #if DEBUG
            if ProcessInfo.processInfo.environment["OPENDISPLAY_RESCUE_RUN"] != nil {
                await Self.dump(observer, "RESCUE before")
                await reconnectAll()
                await Self.dump(observer, "RESCUE after")
                Self.err("RESCUE status: \(status)")
            }
            #endif
        }
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

    /// Restores the recorded arrangement. Runs both recovery paths best-effort — re-enabling a
    /// privately-disabled display (SkyLight transaction) and un-mirroring a mirrored one (public
    /// Core Graphics). Each is a no-op when not applicable, so it's safe to run unconditionally.
    func reconnectAll() async {
        guard let checkpoint else { return }
        busy = true
        defer { busy = false }
        try? await reEnable.recover(to: checkpoint)   // undo a private logical disconnect
        try? await observer.recover(to: checkpoint)   // undo the mirroring fallback
        status = "Reconnect All complete — restored the recorded arrangement."
    }

    #if DEBUG
    private static func dump(_ observer: CoreGraphicsProvider, _ label: String) async {
        let snapshot = await observer.currentSnapshot()
        let summary = snapshot.observations
            .map { "\($0.recordID.rawValue) active=\($0.isActive) mirror=\($0.mirrorSourceID?.rawValue ?? "none")" }
            .joined(separator: " | ")
        err("\(label) online=\(snapshot.observations.count): \(summary)")
    }

    private static func err(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
    #endif
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
