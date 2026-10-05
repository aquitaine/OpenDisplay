#if os(macOS)
import ColorSync  // CGDisplayCreateUUIDFromDisplayID
import CoreGraphics
import Foundation
import TopologyCore

/// What Core Graphics says about every display right now — the rows a `DisplayEventLog` entry
/// carries. Public API only. A logically-disabled display is absent from the online list, so it is
/// absent here too; that absence is itself the datum.
public enum DisplayTruth {
    public static func rows() -> [DisplayEventLog.Row] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(kCFAllocatorDefault, $0.takeRetainedValue()) as String
            }
            let mirror = CGDisplayMirrorsDisplay(id)
            let modes = (CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode])?.count ?? 0
            return DisplayEventLog.Row(
                id: id, uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                builtIn: CGDisplayIsBuiltin(id) != 0, online: CGDisplayIsOnline(id) != 0,
                active: CGDisplayIsActive(id) != 0, asleep: CGDisplayIsAsleep(id) != 0,
                main: CGDisplayIsMain(id) != 0, mirrorOf: mirror == kCGNullDirectDisplay ? nil : mirror,
                width: mode?.width ?? 0, height: mode?.height ?? 0, refreshHz: mode?.refreshRate ?? 0,
                modeCount: modes)
        }
    }
}

/// Builds the diagnostics bundle a user attaches to a bug report: one zip holding everything needed
/// to explain a display problem after the fact — above all issue #40, a monitor macOS refuses to
/// bring back, where the evidence is spread across the window server's saved configuration, the
/// IORegistry's view of the link, and the system log at the moment of connection.
///
/// Read-only towards the system, and local: nothing is uploaded. The user decides whether to share
/// the file. `contents` below is the single description of what goes in, shown in the app and
/// written into the bundle, so the two can't drift.
public enum DiagnosticsBundle {
    public struct AppInfo: Sendable {
        public var version: String
        public var build: String
        public var flavor: String

        public init(version: String, build: String, flavor: String) {
            self.version = version
            self.build = build
            self.flavor = flavor
        }
    }

    /// What the bundle holds, in the words shown to the user before they export.
    public static let contents = [
        "OpenDisplay's own records: the display event timeline, the audit log, the list of displays "
            + "it turned off, its display registry, and its settings (location and app presets removed)",
        "macOS's saved display configuration, now and as copied before recent disconnects",
        "What macOS reports about the displays, the graphics link, and Thunderbolt devices "
            + "(model names and serial numbers of displays and docks)",
        "The last 30 minutes of display-related system log lines"
    ]

    public static func defaultFileName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "OpenDisplay-diagnostics-\(formatter.string(from: now)).zip"
    }

    /// Collects everything into a temporary folder, zips it into `directory`, and returns the zip.
    /// Blocking (it runs `ioreg`, `system_profiler`, and `log show`) — call it off the main actor.
    public static func export(to directory: URL, app: AppInfo, now: Date = Date()) throws -> URL {
        let manager = FileManager.default
        let name = defaultFileName(now: now)
        let staging = manager.temporaryDirectory
            .appendingPathComponent("opendisplay-diag-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        write(summary(app: app, now: now), to: root.appendingPathComponent("summary.json"))
        write(encoded(DisplayTruth.rows()), to: root.appendingPathComponent("displays-now.json"))

        if let support = try? ManagedOfflineStore.defaultDirectory() {
            for file in [DisplayEventLog.fileName, "audit.jsonl", "managed-offline.json", "registry.json",
                         "latest.json", "display-groups.json"] {
                copy(support.appendingPathComponent(file), into: root)
            }
            if let settings = try? Data(contentsOf: support.appendingPathComponent("settings.json")) {
                write(DiagnosticsRedaction.redactedSettings(settings),
                      to: root.appendingPathComponent("settings.redacted.json"))
            }
        }

        let windowServer = root.appendingPathComponent("windowserver", isDirectory: true)
        let current = windowServer.appendingPathComponent("current", isDirectory: true)
        try? manager.createDirectory(at: current, withIntermediateDirectories: true)
        for source in WindowServerConfigBackup.defaultSources() { copy(source, into: current) }
        if let backups = try? WindowServerConfigBackup.defaultDirectory() {
            try? manager.copyItem(at: backups, to: windowServer.appendingPathComponent("before-disconnect"))
        }

        let system = root.appendingPathComponent("system", isDirectory: true)
        try? manager.createDirectory(at: system, withIntermediateDirectories: true)
        for (file, tool, arguments) in commands {
            write(run(tool, arguments), to: system.appendingPathComponent(file))
        }
        write(Data(readme(app: app, now: now).utf8), to: root.appendingPathComponent("README.txt"))

        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent(name)
        try? manager.removeItem(at: zip)
        _ = run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", root.path, zip.path], limitBytes: 0)
        guard manager.fileExists(atPath: zip.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return zip
    }

    // MARK: - Private

    /// The system's view of the displays and the link, plus the display-related log lines. The log
    /// predicate takes the window server's display messages (minus the per-second brightness
    /// commits, which would drown everything else) and the kernel's display-coprocessor lines.
    private static let commands: [(file: String, tool: String, arguments: [String])] = [
        ("system-profiler.json", "/usr/sbin/system_profiler",
         ["SPDisplaysDataType", "SPThunderboltDataType", "-json"]),
        ("ioreg-framebuffers.txt", "/usr/sbin/ioreg", ["-lw0", "-r", "-c", "IOMobileFramebuffer"]),
        ("ioreg-displayport.txt", "/usr/sbin/ioreg", ["-lw0", "-r", "-c", "AppleDCPDPTXRemotePortProxy"]),
        ("ioreg-avservice.txt", "/usr/sbin/ioreg", ["-lw0", "-r", "-c", "DCPAVServiceProxy"]),
        ("display-log.txt", "/usr/bin/log",
         ["show", "--last", "30m", "--style", "compact", "--predicate",
          "(process == \"WindowServer\" AND eventMessage CONTAINS[c] \"display\" "
            + "AND NOT category == \"Brightness\") "
            + "OR (process == \"kernel\" AND (eventMessage CONTAINS \"DCP\" "
            + "OR eventMessage CONTAINS[c] \"dptx\" OR eventMessage CONTAINS[c] \"dispext\"))"])
    ]

    private static func summary(app: AppInfo, now: Date) -> Data? {
        let info = ProcessInfo.processInfo
        let fields: [String: String] = [
            "exportedAt": ISO8601DateFormatter().string(from: now),
            "appVersion": app.version, "appBuild": app.build, "appFlavor": app.flavor,
            "macOS": info.operatingSystemVersionString,
            "model": sysctl("hw.model"), "chip": sysctl("machdep.cpu.brand_string")
        ]
        return try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
    }

    private static func readme(app: AppInfo, now: Date) -> String {
        """
        OpenDisplay diagnostics bundle
        Exported \(ISO8601DateFormatter().string(from: now)) by OpenDisplay \(app.version) (\(app.build), \(app.flavor))

        This file was created on your Mac and has not been sent anywhere. Attach it to your issue at
        https://github.com/aquitaine/OpenDisplay/issues if you are happy to share it.

        What is inside:
        \(contents.map { "  - \($0)" }.joined(separator: "\n"))

        It does not contain window titles, file names, screen contents, or your location.
        """
    }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private static func encoded(_ rows: [DisplayEventLog.Row]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(rows)
    }

    private static func write(_ data: Data?, to url: URL) {
        guard let data, !data.isEmpty else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func copy(_ source: URL, into folder: URL) {
        try? FileManager.default.copyItem(
            at: source, to: folder.appendingPathComponent(source.lastPathComponent))
    }

    /// Runs one tool and returns its output, capped so a chatty log can't produce a bundle too big
    /// to attach, and time-limited so a hung tool can't hang the export.
    private static func run(_ tool: String, _ arguments: [String],
                            limitBytes: Int = 4 * 1024 * 1024, timeout: TimeInterval = 40) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        var data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        if limitBytes > 0, data.count > limitBytes {
            data = Data("[truncated to the newest \(limitBytes) bytes]\n".utf8) + data.suffix(limitBytes)
        }
        return data
    }
}
#endif
