import XCTest
@testable import DisplayDomain

final class DDCServiceMatcherTests: XCTestCase {
    private typealias Matcher = DDCServiceMatcher

    // MARK: - PnP vendor decode

    func testVendorNumberFromPNPKnownVendors() {
        // Reference values from the UEFI PnP registry: these are the wire values EDID carries.
        XCTAssertEqual(Matcher.vendorNumber(fromPNP: "SAM"), 0x4C2D)  // Samsung
        XCTAssertEqual(Matcher.vendorNumber(fromPNP: "GSM"), 0x1E6D)  // LG
        XCTAssertEqual(Matcher.vendorNumber(fromPNP: "DEL"), 0x10AC)  // Dell
        XCTAssertEqual(Matcher.vendorNumber(fromPNP: "gsm"), 0x1E6D)  // case-insensitive
    }

    func testVendorNumberFromPNPRejectsMalformed() {
        XCTAssertNil(Matcher.vendorNumber(fromPNP: ""))
        XCTAssertNil(Matcher.vendorNumber(fromPNP: "SA"))
        XCTAssertNil(Matcher.vendorNumber(fromPNP: "SAMS"))
        XCTAssertNil(Matcher.vendorNumber(fromPNP: "S4M"))
    }

    // MARK: - Scoring

    func testScoreWeightsSerialOverProductOverVendor() {
        let target = Matcher.Target(vendorNumber: 0x4C2D, productNumber: 0x1001, serialNumber: 777)
        let vendorOnly = Matcher.Candidate(legacyManufacturerID: 0x4C2D)
        let productOnly = Matcher.Candidate(productID: 0x1001)
        let serialOnly = Matcher.Candidate(serialNumber: 777)
        // serial (4) > product (2) > vendor (1); product+vendor (3) still loses to serial.
        XCTAssertEqual(Matcher.score(vendorOnly, against: target), 1)
        XCTAssertEqual(Matcher.score(productOnly, against: target), 2)
        XCTAssertEqual(Matcher.score(serialOnly, against: target), 4)
        let vendorAndProduct = Matcher.Candidate(legacyManufacturerID: 0x4C2D, productID: 0x1001)
        XCTAssertLessThan(Matcher.score(vendorAndProduct, against: target),
                          Matcher.score(serialOnly, against: target))
    }

    func testScoreFallsBackToPNPStringWhenLegacyIDMissing() {
        let target = Matcher.Target(vendorNumber: 0x1E6D, productNumber: 0, serialNumber: 0)
        XCTAssertEqual(Matcher.score(.init(manufacturerID: "GSM"), against: target), 1)
    }

    func testScoreIgnoresZeroFields() {
        // Serial 0 = "not programmed" on both sides; matching 0 == 0 would pair any two such panels.
        let target = Matcher.Target(vendorNumber: 0, productNumber: 0, serialNumber: 0)
        let zeros = Matcher.Candidate(legacyManufacturerID: 0, productID: 0, serialNumber: 0)
        XCTAssertEqual(Matcher.score(zeros, against: target), 0)
    }

    // MARK: - Index selection

    func testBestIndexPicksIdentityMatchOverOrder() {
        // The regression this exists for: CG order says index 0, identity says index 1.
        let target = Matcher.Target(vendorNumber: 0x4C2D, productNumber: 0x1001, serialNumber: 777)
        let candidates: [Matcher.Candidate?] = [
            .init(legacyManufacturerID: 0x10AC, productID: 0x2002, serialNumber: 111),  // the Dell
            .init(legacyManufacturerID: 0x4C2D, productID: 0x1001, serialNumber: 777),  // the Samsung
        ]
        XCTAssertEqual(Matcher.bestIndex(of: candidates, against: target, fallbackIndex: 0), 1)
    }

    func testBestIndexFallsBackToOrderWhenNoAttributes() {
        let target = Matcher.Target(vendorNumber: 0x4C2D, productNumber: 0x1001, serialNumber: 777)
        XCTAssertEqual(Matcher.bestIndex(of: [nil, nil, nil], against: target, fallbackIndex: 2), 2)
        // Fallback index beyond the array clamps rather than crashing (CG saw more displays than IOKit).
        XCTAssertEqual(Matcher.bestIndex(of: [nil, nil], against: target, fallbackIndex: 5), 1)
        XCTAssertNil(Matcher.bestIndex(of: [], against: target, fallbackIndex: 0))
    }

    func testBestIndexTieBetweenIdenticalMonitorsPrefersOrder() {
        // Two identical panels with unprogrammed serials tie on vendor+product — order is the only
        // remaining signal, so the fallback (order) choice must win, for BOTH fallback values.
        let target = Matcher.Target(vendorNumber: 0x4C2D, productNumber: 0x1001, serialNumber: 0)
        let twin = Matcher.Candidate(legacyManufacturerID: 0x4C2D, productID: 0x1001, serialNumber: 0)
        XCTAssertEqual(Matcher.bestIndex(of: [twin, twin], against: target, fallbackIndex: 0), 0)
        XCTAssertEqual(Matcher.bestIndex(of: [twin, twin], against: target, fallbackIndex: 1), 1)
    }

    func testBestIndexUniqueWinnerBeatsTiedFallback() {
        // A strictly better identity match wins even when the fallback points elsewhere.
        let target = Matcher.Target(vendorNumber: 0x4C2D, productNumber: 0x1001, serialNumber: 777)
        let candidates: [Matcher.Candidate?] = [
            .init(legacyManufacturerID: 0x4C2D, productID: 0x1001, serialNumber: 0),    // model match only
            .init(legacyManufacturerID: 0x4C2D, productID: 0x1001, serialNumber: 777),  // exact unit
        ]
        XCTAssertEqual(Matcher.bestIndex(of: candidates, against: target, fallbackIndex: 0), 1)
    }
}
