import XCTest
@testable import AutomationSchema

final class DDCCapabilitiesTests: XCTestCase {
    func testParsesSimpleVCPList() {
        let caps = DDCCapabilities.parse("vcp(10 12 60 D6)")
        XCTAssertNotNil(caps)
        XCTAssertEqual(caps?.supportedVCPCodes, [0x10, 0x12, 0x60, 0xD6])
        XCTAssertTrue(caps!.discreteValues.isEmpty)
    }

    func testParsesDiscreteValues() {
        let caps = DDCCapabilities.parse("vcp(14(05 08 0B) 60(01 03 11) D6(01 04 05))")
        XCTAssertEqual(caps?.supportedVCPCodes, [0x14, 0x60, 0xD6])
        XCTAssertEqual(caps?.values(for: 0x14), [0x05, 0x08, 0x0B])
        XCTAssertEqual(caps?.values(for: 0x60), [0x01, 0x03, 0x11])
        XCTAssertEqual(caps?.values(for: 0xD6), [0x01, 0x04, 0x05])
    }

    func testParsesFullRealisticCapabilitiesString() {
        let s = "(prot(monitor)type(lcd)model(VG259)cmds(01 02 03 0C E3 F3)" +
                "vcp(02 04 05 08 10 12 14(05 08 0B) 16 18 1A 60(01 03 11) 6C 6E 70 86(02 05) D6(01 04 05) DF)" +
                "mswhql(1)mccs_ver(2.1))"
        let caps = DDCCapabilities.parse(s)
        XCTAssertNotNil(caps)
        XCTAssertTrue(caps!.supports(0x10))   // brightness
        XCTAssertTrue(caps!.supports(0x12))   // contrast
        XCTAssertTrue(caps!.supports(0x60))   // input source
        XCTAssertTrue(caps!.supports(0xD6))   // power
        XCTAssertFalse(caps!.supports(0x62))  // volume NOT advertised
        XCTAssertEqual(caps!.values(for: 0x60), [0x01, 0x03, 0x11])
        // The cmds(...) list (commands, not features) must not leak into VCP codes.
        XCTAssertFalse(caps!.supports(0xF3))
        XCTAssertEqual(caps!.raw, s)
    }

    func testCaseInsensitiveLabelAndHex() {
        let caps = DDCCapabilities.parse("VCP(10 1a D6(01 04))")
        XCTAssertEqual(caps?.supportedVCPCodes, [0x10, 0x1A, 0xD6])
        XCTAssertEqual(caps?.values(for: 0xD6), [0x01, 0x04])
    }

    func testNoVCPBlockReturnsNil() {
        XCTAssertNil(DDCCapabilities.parse("(prot(monitor)type(lcd)cmds(01 02))"))
        XCTAssertNil(DDCCapabilities.parse(""))
        XCTAssertNil(DDCCapabilities.parse("garbage"))
    }

    func testEmptyVCPBlockReturnsNil() {
        XCTAssertNil(DDCCapabilities.parse("vcp()"))
        XCTAssertNil(DDCCapabilities.parse("vcp(   )"))
    }

    func testUnbalancedParensReturnsNil() {
        XCTAssertNil(DDCCapabilities.parse("vcp(10 12 60"))          // never closed
        XCTAssertNil(DDCCapabilities.parse("vcp(10 14(05 08 60)"))   // outer never closed
    }

    func testDuplicateCodesCollapse() {
        let caps = DDCCapabilities.parse("vcp(10 10 12 12 12)")
        XCTAssertEqual(caps?.supportedVCPCodes, [0x10, 0x12])
    }

    func testToleratesExtraWhitespaceAndNewlines() {
        let caps = DDCCapabilities.parse("vcp(\n  10   12\t60(01  03)\n  D6 )")
        XCTAssertEqual(caps?.supportedVCPCodes, [0x10, 0x12, 0x60, 0xD6])
        XCTAssertEqual(caps?.values(for: 0x60), [0x01, 0x03])
    }

    func testValuesForUnlistedFeatureIsNil() {
        let caps = DDCCapabilities.parse("vcp(10 12)")
        XCTAssertNil(caps?.values(for: 0x10))     // continuous, no discrete list
        XCTAssertNil(caps?.values(for: 0x99))     // not supported at all
        XCTAssertFalse(caps!.supports(0x99))
    }

    func testCodableRoundTrips() throws {
        let caps = DDCCapabilities.parse("vcp(10 60(01 03 11))")!
        let data = try JSONEncoder().encode(caps)
        let back = try JSONDecoder().decode(DDCCapabilities.self, from: data)
        XCTAssertEqual(back, caps)
    }

    // Regression: VCP 0x14 (Select Color Preset) is a non-continuous enum. The colour-mode menu must
    // offer the panel's *advertised* preset codes, not a contiguous 1...max range — otherwise the user
    // picks codes the monitor never listed and the write is a silent no-op ("shows, but does nothing").
    func testOfferedValuesUsesAdvertisedDiscreteValuesForColorPreset() {
        let caps = DDCCapabilities.parse("vcp(10 12 14(05 08 0B) 60(01 03 11) D6(01 04 05))")!
        // The bug offered [1,2,3,4,5]; the fix offers exactly the advertised set.
        XCTAssertEqual(DDCCapabilities.offeredValues(caps, for: 0x14, fallbackMax: 5), [5, 8, 11])
        XCTAssertEqual(DDCCapabilities.offeredValues(caps, for: 0x60, fallbackMax: 99), [1, 3, 17])
    }

    func testOfferedValuesFallsBackToRangeWhenCapabilitiesUnavailable() {
        // No capabilities read yet → fall back to the 1...max guess (best-effort).
        XCTAssertEqual(DDCCapabilities.offeredValues(nil, for: 0x14, fallbackMax: 5), [1, 2, 3, 4, 5])
        // Capabilities present but this code wasn't enumerated (continuous, or no discrete list) → fallback.
        let caps = DDCCapabilities.parse("vcp(10 14)")!
        XCTAssertEqual(DDCCapabilities.offeredValues(caps, for: 0x14, fallbackMax: 3), [1, 2, 3])
        // Degenerate fallback max → empty, never a crash.
        XCTAssertEqual(DDCCapabilities.offeredValues(nil, for: 0x14, fallbackMax: 0), [])
    }
}
