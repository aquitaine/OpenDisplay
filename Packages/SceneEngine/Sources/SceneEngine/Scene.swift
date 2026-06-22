import DisplayDomain
import Foundation

/// A named, partial desired state for displays. Omitted fields are left unchanged — a scene only
/// asserts what it explicitly sets (PRD §13.2, TOP-010).
public struct Scene: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var schemaVersion: String
    public var members: [Member]
    public var policy: Policy

    public init(
        id: String,
        name: String,
        schemaVersion: String = "1.0",
        members: [Member],
        policy: Policy = Policy()
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.members = members
        self.policy = policy
    }

    /// One participant in a scene: a selector, whether it is required, and the fields to assert.
    public struct Member: Hashable, Sendable, Codable {
        public var selector: String
        public var required: Bool
        public var desired: DesiredState

        public init(selector: String, required: Bool, desired: DesiredState) {
            self.selector = selector
            self.required = required
            self.desired = desired
        }
    }

    public struct Policy: Hashable, Sendable, Codable {
        public enum MissingOptional: String, Hashable, Sendable, Codable {
            case continueApplying
            case skip
        }
        public enum UnsupportedField: String, Hashable, Sendable, Codable {
            case warn
            case fail
        }
        public enum WindowPlacement: String, Hashable, Sendable, Codable {
            case unchanged
            case restore
        }

        public var missingOptional: MissingOptional
        public var unsupportedField: UnsupportedField
        public var windowPlacement: WindowPlacement
        public var rollbackOnRequiredFailure: Bool

        public init(
            missingOptional: MissingOptional = .continueApplying,
            unsupportedField: UnsupportedField = .warn,
            windowPlacement: WindowPlacement = .unchanged,
            rollbackOnRequiredFailure: Bool = true
        ) {
            self.missingOptional = missingOptional
            self.unsupportedField = unsupportedField
            self.windowPlacement = windowPlacement
            self.rollbackOnRequiredFailure = rollbackOnRequiredFailure
        }
    }
}

/// The independently-applied fields a scene member may assert. Each is optional; `nil` means
/// "leave as-is" (PRD §13.2 desired-state).
public struct DesiredState: Hashable, Sendable, Codable {
    public var connected: Bool?
    public var main: Bool?
    public var position: DisplayOrigin?
    public var relativePosition: RelativePosition?
    public var mode: DisplayMode?
    public var rotation: Rotation?
    public var brightness: Double?
    public var colorProfile: String?
    public var hdr: Bool?

    public init(
        connected: Bool? = nil,
        main: Bool? = nil,
        position: DisplayOrigin? = nil,
        relativePosition: RelativePosition? = nil,
        mode: DisplayMode? = nil,
        rotation: Rotation? = nil,
        brightness: Double? = nil,
        colorProfile: String? = nil,
        hdr: Bool? = nil
    ) {
        self.connected = connected
        self.main = main
        self.position = position
        self.relativePosition = relativePosition
        self.mode = mode
        self.rotation = rotation
        self.brightness = brightness
        self.colorProfile = colorProfile
        self.hdr = hdr
    }

    public struct RelativePosition: Hashable, Sendable, Codable {
        public var relativeToSelector: String
        public var edge: DisplaySelector.TopologyEdge
        public var gap: Int

        public init(relativeToSelector: String, edge: DisplaySelector.TopologyEdge, gap: Int = 0) {
            self.relativeToSelector = relativeToSelector
            self.edge = edge
            self.gap = gap
        }
    }
}
