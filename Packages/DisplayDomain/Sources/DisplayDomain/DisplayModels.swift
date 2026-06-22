import Foundation

/// Broad classification of a display endpoint. Drives capability gating and copy.
public enum DisplayClass: String, Hashable, Sendable, Codable {
    case builtIn
    case external
    case projector
    case television
    case sidecar
    case airplay
    case virtual
    case headlessAdapter
    case unknown
}

/// The physical/logical path from the Mac to the display. Capability detection is per-route
/// because a monitor may support DDC directly but not through a dock or KVM (PRD §6.2, REG-008).
public enum ConnectionTransport: String, Hashable, Sendable, Codable {
    case internalPanel
    case usbCDisplayPort
    case thunderbolt
    case hdmi
    case displayPort
    case dock
    case kvm
    case wireless
    case virtual
    case unknown
}

/// A concrete display mode. Modes are resolved by *properties*, never by transient mode
/// handles, because the available mode list can change after reconnect (PRD TOP-005, S24).
public struct DisplayMode: Hashable, Sendable, Codable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var pointWidth: Int
    public var pointHeight: Int
    public var refreshHz: Double
    public var isHiDPI: Bool
    public var bitDepth: Int?

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        pointWidth: Int,
        pointHeight: Int,
        refreshHz: Double,
        isHiDPI: Bool,
        bitDepth: Int? = nil
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refreshHz = refreshHz
        self.isHiDPI = isHiDPI
        self.bitDepth = bitDepth
    }
}

public enum Rotation: Int, Hashable, Sendable, Codable, CaseIterable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

/// A point in the global desktop coordinate space (top-left origin), in points.
public struct DisplayOrigin: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = DisplayOrigin(x: 0, y: 0)
}

/// An immutable snapshot of what macOS/providers currently report for one endpoint, tied to
/// the topology generation in which it was observed (PRD §13.1 DisplayObservation). Observed
/// state is deliberately kept separate from desired state (REG-009).
public struct DisplayObservation: Hashable, Sendable, Codable {
    public var recordID: DisplayRecordID
    public var cgDisplayID: UInt32?
    public var cgUUID: String?
    public var ioServicePath: String?
    public var isActive: Bool
    public var overlay: PresentationOverlay
    public var origin: DisplayOrigin
    public var mode: DisplayMode?
    public var rotation: Rotation
    public var isMain: Bool
    public var mirrorSourceID: DisplayRecordID?
    public var hdrEnabled: Bool
    public var colorProfileName: String?
    public var transport: ConnectionTransport
    public var displayClass: DisplayClass
    public var generation: TopologyGeneration
    public var observedAt: Date

    public init(
        recordID: DisplayRecordID,
        cgDisplayID: UInt32? = nil,
        cgUUID: String? = nil,
        ioServicePath: String? = nil,
        isActive: Bool,
        overlay: PresentationOverlay = .visible,
        origin: DisplayOrigin = .zero,
        mode: DisplayMode? = nil,
        rotation: Rotation = .degrees0,
        isMain: Bool = false,
        mirrorSourceID: DisplayRecordID? = nil,
        hdrEnabled: Bool = false,
        colorProfileName: String? = nil,
        transport: ConnectionTransport = .unknown,
        displayClass: DisplayClass = .unknown,
        generation: TopologyGeneration,
        observedAt: Date = Date()
    ) {
        self.recordID = recordID
        self.cgDisplayID = cgDisplayID
        self.cgUUID = cgUUID
        self.ioServicePath = ioServicePath
        self.isActive = isActive
        self.overlay = overlay
        self.origin = origin
        self.mode = mode
        self.rotation = rotation
        self.isMain = isMain
        self.mirrorSourceID = mirrorSourceID
        self.hdrEnabled = hdrEnabled
        self.colorProfileName = colorProfileName
        self.transport = transport
        self.displayClass = displayClass
        self.generation = generation
        self.observedAt = observedAt
    }

    /// `true` when this display is mirroring another endpoint.
    public var isMirrored: Bool { mirrorSourceID != nil }
}

/// The persistent record that user intent (alias, tags, pairing, policies) attaches to. It is
/// linked to observations through scored identity evidence (PRD §10.5). Persists across the
/// active/offline lifecycle (REG-006).
public struct DisplayRecord: Hashable, Sendable, Codable, Identifiable {
    public var id: DisplayRecordID
    public var alias: String?
    public var tags: Set<String>
    public var fingerprint: DisplayFingerprint
    public var displayClass: DisplayClass
    public var lastSeen: Date?
    public var pairingConfirmed: Bool

    public init(
        id: DisplayRecordID,
        alias: String? = nil,
        tags: Set<String> = [],
        fingerprint: DisplayFingerprint,
        displayClass: DisplayClass = .unknown,
        lastSeen: Date? = nil,
        pairingConfirmed: Bool = false
    ) {
        self.id = id
        self.alias = alias
        self.tags = tags
        self.fingerprint = fingerprint
        self.displayClass = displayClass
        self.lastSeen = lastSeen
        self.pairingConfirmed = pairingConfirmed
    }

    /// A user-facing name: the explicit alias if set, otherwise the model name, otherwise the ID.
    public var displayName: String {
        alias ?? fingerprint.modelName ?? id.rawValue
    }
}
