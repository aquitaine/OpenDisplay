import Foundation

/// The multi-signal identity evidence for a display. A display ID is an observation, not an
/// identity (PRD principle 2.1); persistent behavior uses this scored fingerprint plus user
/// confirmation rather than any single signal (REG-003).
public struct DisplayFingerprint: Hashable, Sendable, Codable {
    public var vendorID: Int?
    public var productID: Int?
    public var serialNumber: String?
    /// Salted hash of the serial used for export/correlation without leaking the raw value
    /// (PRD §13.3, DIA-011).
    public var serialHash: String?
    public var modelName: String?
    public var manufactureYear: Int?
    public var manufactureWeek: Int?
    public var physicalWidthMM: Int?
    public var physicalHeightMM: Int?
    public var edidHash: String?

    public init(
        vendorID: Int? = nil,
        productID: Int? = nil,
        serialNumber: String? = nil,
        serialHash: String? = nil,
        modelName: String? = nil,
        manufactureYear: Int? = nil,
        manufactureWeek: Int? = nil,
        physicalWidthMM: Int? = nil,
        physicalHeightMM: Int? = nil,
        edidHash: String? = nil
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.serialHash = serialHash
        self.modelName = modelName
        self.manufactureYear = manufactureYear
        self.manufactureWeek = manufactureWeek
        self.physicalWidthMM = physicalWidthMM
        self.physicalHeightMM = physicalHeightMM
        self.edidHash = edidHash
    }
}

/// One piece of evidence linking an observation to a record, with the weight it contributes.
public struct IdentityEvidence: Hashable, Sendable, Codable {
    public enum Signal: String, Hashable, Sendable, Codable {
        case userAlias
        case explicitPairing
        case edidSerial
        case modelFamily
        case ioRegistryPath
        case physicalSize
        case topologyPosition
        case cgUUID
    }

    public var signal: Signal
    public var matched: Bool
    public var weight: Double

    public init(signal: Signal, matched: Bool, weight: Double) {
        self.signal = signal
        self.matched = matched
        self.weight = weight
    }
}

/// The result of matching an observation against a candidate record: a 0...1 confidence score
/// plus the evidence that produced it, so the UI/API can explain *why* (REG-005).
public struct IdentityConfidence: Hashable, Sendable, Codable {
    public var score: Double
    public var evidence: [IdentityEvidence]

    public init(score: Double, evidence: [IdentityEvidence]) {
        self.score = min(1, max(0, score))
        self.evidence = evidence
    }

    /// Default threshold below which a destructive (lifecycle) operation must not proceed
    /// without explicit user confirmation (LIF-004, §9.2 invariant 4).
    public static let destructiveThreshold = 0.85
}

/// Pure, deterministic identity scoring. Higher-trust signals dominate; identical monitors that
/// share model family but differ only by route/topology stay below the destructive threshold
/// until the user confirms an explicit pairing (REG-004).
public enum IdentityScorer {
    /// Canonical signal weights. They intentionally sum so that a confirmed serial OR an
    /// explicit user pairing alone clears the destructive threshold, while model-family +
    /// topology evidence alone does not.
    public static let weights: [IdentityEvidence.Signal: Double] = [
        .explicitPairing: 0.90,
        .userAlias: 0.45,
        .edidSerial: 0.85,
        .modelFamily: 0.25,
        .ioRegistryPath: 0.30,
        .physicalSize: 0.10,
        .topologyPosition: 0.20,
        .cgUUID: 0.15
    ]

    public static func score(observed: DisplayFingerprint,
                             candidate: DisplayRecord,
                             explicitPairing: Bool = false,
                             aliasMatches: Bool = false,
                             ioPathMatches: Bool = false,
                             topologyMatches: Bool = false,
                             cgUUIDMatches: Bool = false) -> IdentityConfidence {
        var evidence: [IdentityEvidence] = []

        func add(_ signal: IdentityEvidence.Signal, _ matched: Bool) {
            evidence.append(IdentityEvidence(signal: signal, matched: matched, weight: weights[signal] ?? 0))
        }

        add(.explicitPairing, explicitPairing || candidate.pairingConfirmed)
        add(.userAlias, aliasMatches)

        let serialMatches: Bool = {
            guard let a = observed.serialNumber ?? observed.serialHash,
                  let b = candidate.fingerprint.serialNumber ?? candidate.fingerprint.serialHash
            else { return false }
            return a == b
        }()
        add(.edidSerial, serialMatches)

        let modelMatches = observed.vendorID != nil
            && observed.vendorID == candidate.fingerprint.vendorID
            && observed.productID == candidate.fingerprint.productID
        add(.modelFamily, modelMatches)

        add(.ioRegistryPath, ioPathMatches)
        add(.physicalSize, observed.physicalWidthMM != nil
            && observed.physicalWidthMM == candidate.fingerprint.physicalWidthMM
            && observed.physicalHeightMM == candidate.fingerprint.physicalHeightMM)
        add(.topologyPosition, topologyMatches)
        add(.cgUUID, cgUUIDMatches)

        // Combine matched weights with diminishing returns so multiple weak signals never
        // silently exceed a single strong one. score = 1 - Π(1 - weightᵢ) over matched signals.
        let product = evidence.reduce(1.0) { acc, item in
            item.matched ? acc * (1 - item.weight) : acc
        }
        return IdentityConfidence(score: 1 - product, evidence: evidence)
    }
}
