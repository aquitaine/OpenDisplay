import DisplayDomain
import Foundation

/// The stable, versioned result envelope returned by every automation surface (CLI, App Intents,
/// HTTP API). Schema is versioned independently of the app; clients must ignore unknown fields
/// (PRD §12.4, §12.7, AUT-003/004/012).
public struct ResultEnvelope: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = "1.0"

    public enum Status: String, Hashable, Sendable, Codable {
        case committed
        case partial
        case rolledBack
        case failed
        case noOp
    }

    public var schemaVersion: String
    public var transactionId: String
    public var status: Status
    public var actor: Actor
    public var requestedAt: Date
    public var topologyGeneration: UInt64
    public var targets: [TargetResult]
    public var recovery: RecoveryInfo?
    public var errors: [ErrorInfo]

    public init(
        schemaVersion: String = ResultEnvelope.currentSchemaVersion,
        transactionId: String,
        status: Status,
        actor: Actor,
        requestedAt: Date,
        topologyGeneration: UInt64,
        targets: [TargetResult] = [],
        recovery: RecoveryInfo? = nil,
        errors: [ErrorInfo] = []
    ) {
        self.schemaVersion = schemaVersion
        self.transactionId = transactionId
        self.status = status
        self.actor = actor
        self.requestedAt = requestedAt
        self.topologyGeneration = topologyGeneration
        self.targets = targets
        self.recovery = recovery
        self.errors = errors
    }

    public struct TargetResult: Hashable, Sendable, Codable {
        public var displayId: String
        public var alias: String?
        public var identityConfidence: Double
        public var operations: [OperationResult]

        public init(displayId: String, alias: String?, identityConfidence: Double, operations: [OperationResult]) {
            self.displayId = displayId
            self.alias = alias
            self.identityConfidence = identityConfidence
            self.operations = operations
        }
    }

    public struct OperationResult: Hashable, Sendable, Codable {
        public var field: String
        public var requested: AnyCodableValue?
        public var observed: AnyCodableValue?
        public var verification: VerificationState
        public var provider: String?
        public var warnings: [String]

        public init(
            field: String,
            requested: AnyCodableValue? = nil,
            observed: AnyCodableValue? = nil,
            verification: VerificationState,
            provider: String? = nil,
            warnings: [String] = []
        ) {
            self.field = field
            self.requested = requested
            self.observed = observed
            self.verification = verification
            self.provider = provider
            self.warnings = warnings
        }
    }

    public struct RecoveryInfo: Hashable, Sendable, Codable {
        public var checkpointId: String
        public var available: Bool

        public init(checkpointId: String, available: Bool) {
            self.checkpointId = checkpointId
            self.available = available
        }
    }

    public struct ErrorInfo: Hashable, Sendable, Codable {
        public var code: String
        public var message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }
}

/// A minimal JSON value wrapper so operation `requested`/`observed` can carry bool/number/string
/// without leaking concrete Swift types into the wire schema.
public enum AnyCodableValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

public extension ResultEnvelope {
    /// Canonical encoder used across all automation surfaces: stable key order + ISO-8601 dates.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
