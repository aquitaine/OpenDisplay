import XCTest
@testable import DisplayDomain

final class IdentityScorerTests: XCTestCase {
    private func record(serial: String?, vendor: Int? = 610, product: Int? = 123, paired: Bool = false) -> DisplayRecord {
        DisplayRecord(
            id: .generate(),
            fingerprint: DisplayFingerprint(vendorID: vendor, productID: product, serialNumber: serial, modelName: "Test 4K"),
            pairingConfirmed: paired
        )
    }

    func testMatchingSerialClearsDestructiveThreshold() {
        let candidate = record(serial: "ABC123")
        let observed = DisplayFingerprint(vendorID: 610, productID: 123, serialNumber: "ABC123")
        let confidence = IdentityScorer.score(observed: observed, candidate: candidate)
        XCTAssertGreaterThanOrEqual(confidence.score, IdentityConfidence.destructiveThreshold,
                                    "A matching EDID serial must be enough to act destructively.")
    }

    func testIdenticalModelWithoutSerialStaysBelowThreshold() {
        // Two identical monitors: same vendor/product, no serial, only topology evidence. This must
        // NOT clear the destructive threshold without explicit pairing (REG-004, §9.2 invariant 4).
        let candidate = record(serial: nil)
        let observed = DisplayFingerprint(vendorID: 610, productID: 123, serialNumber: nil)
        let confidence = IdentityScorer.score(observed: observed, candidate: candidate, topologyMatches: true)
        XCTAssertLessThan(confidence.score, IdentityConfidence.destructiveThreshold)
    }

    func testExplicitPairingClearsThreshold() {
        let candidate = record(serial: nil, paired: true)
        let observed = DisplayFingerprint(vendorID: 610, productID: 123, serialNumber: nil)
        let confidence = IdentityScorer.score(observed: observed, candidate: candidate, explicitPairing: true)
        XCTAssertGreaterThanOrEqual(confidence.score, IdentityConfidence.destructiveThreshold)
    }

    func testScoreIsClampedToUnitInterval() {
        let candidate = record(serial: "ABC123", paired: true)
        let observed = DisplayFingerprint(vendorID: 610, productID: 123, serialNumber: "ABC123")
        let confidence = IdentityScorer.score(observed: observed, candidate: candidate,
                                              explicitPairing: true, aliasMatches: true,
                                              ioPathMatches: true, topologyMatches: true, cgUUIDMatches: true)
        XCTAssertLessThanOrEqual(confidence.score, 1.0)
        XCTAssertGreaterThanOrEqual(confidence.score, 0.0)
    }
}
