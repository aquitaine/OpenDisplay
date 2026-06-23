#if os(macOS)
import CoreGraphics
import Foundation

/// Whether rotation *writes* are available. Reading orientation always works (public CGDisplayRotation);
/// only setting it needs a backend, and there is no Apple-supported rotation setter — so the stable
/// build is read-only and a private path stays strictly experimental (PRD: safety before capability).
enum RotationCapability: Equatable {
    case readOnly
    case experimental
    case unavailable(reason: String)
}

enum RotationError: Error, Equatable {
    case unsupported(String)
    case invalidAngle
    case displayOffline
    case unsafe(String)
    case verificationFailed
}

/// Reads + (maybe) writes a display's rotation. The UI and scene model depend only on this protocol,
/// so swapping in the experimental backend never touches them.
protocol RotationBackend: Sendable {
    var capability: RotationCapability { get }
    /// Current rotation in degrees (0/90/180/270) via public Core Graphics.
    func currentRotation(for displayID: CGDirectDisplayID) -> Int
    /// Sets rotation. The stable backend always throws `.unsupported`.
    func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) async throws
}

extension RotationBackend {
    /// Valid quarter-turn angles.
    static var validAngles: [Int] { [0, 90, 180, 270] }
}

/// The stable, App-Store-safe backend: reads rotation via public Core Graphics, refuses all writes.
/// This is the default everywhere; the experimental SkyLight backend is opt-in and never the default.
struct ReadOnlyRotationBackend: RotationBackend {
    static let unavailableReason = "Rotation changes are not safely supported on this macOS version."

    var capability: RotationCapability { .unavailable(reason: Self.unavailableReason) }

    func currentRotation(for displayID: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(displayID).rounded())
    }

    func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) async throws {
        throw RotationError.unsupported(Self.unavailableReason)
    }
}

#if !PUBLIC_API_ONLY
/// EXPERIMENTAL rotation backend — opt-in only, never the default, compiled out of App Store builds.
/// Runs the private rotation through the `opendisplay` helper's gated `_rotate-exp` command in a
/// short-lived isolated process, so a WindowServer-client crash kills only the helper, not the app.
/// The helper does its own angle/display validation, post-rotation verification, and rollback.
struct ExperimentalRotationBackend: RotationBackend {
    var capability: RotationCapability { .experimental }

    func currentRotation(for displayID: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(displayID).rounded())
    }

    func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) async throws {
        guard Self.validAngles.contains(degrees) else { throw RotationError.invalidAngle }
        guard let helper = Self.helperURL else { throw RotationError.unsupported("rotation helper not found") }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["_rotate-exp", String(displayID), String(degrees)]
        process.environment = ProcessInfo.processInfo.environment
            .merging(["OPENDISPLAY_EXPERIMENTAL_ROTATION": "1"]) { _, new in new }
        // Await the helper's verified exit WITHOUT blocking a cooperative-pool thread for the whole
        // rotation (spawn + private rotation + verification + possible rollback): resume from the
        // termination handler instead of Process.waitUntilExit(). The helper does its own angle/display
        // validation, post-rotation verification, and rollback; success gates strictly on exit code 0.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RotationError.verificationFailed)
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Locate the `opendisplay` helper: shipped under Contents/Helpers in a release bundle, or sitting
    /// beside the .app in the build-products dir during development.
    private static var helperURL: URL? {
        var candidates: [URL] = []
        if let macOS = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(macOS.deletingLastPathComponent().appendingPathComponent("Helpers/opendisplay"))
        }
        // Dev: the CLI is a sibling of OpenDisplay.app in the build-products directory.
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("opendisplay"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
#endif
#endif
