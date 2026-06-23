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
#endif
