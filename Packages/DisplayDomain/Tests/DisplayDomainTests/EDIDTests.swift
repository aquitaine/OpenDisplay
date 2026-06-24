import XCTest
@testable import DisplayDomain

final class EDIDTests: XCTestCase {
    /// Builds a valid 128-byte EDID base block with a `0xFC` monitor-name descriptor (offset 54) and a
    /// detailed-timing descriptor (offset 72), then fixes byte 127 so the checksum is valid.
    private func makeEDID(
        mfg: (UInt8, UInt8) = (0x4C, 0x2D),                    // "SAM"
        product: Int = 0x1234, serial: UInt32 = 0x0A0B0C0D,
        week: UInt8 = 10, year: UInt8 = 33,                    // 1990 + 33 = 2023
        version: UInt8 = 1, revision: UInt8 = 4,
        widthCm: UInt8 = 75, heightCm: UInt8 = 32, gamma: UInt8 = 120,   // (120+100)/100 = 2.2
        monitorName: String = "S34J55x",
        timing: (h: Int, v: Int)? = (3440, 1440),
        extensions: UInt8 = 0,
        validChecksum: Bool = true
    ) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 128)
        b.replaceSubrange(0..<8, with: [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        b[8] = mfg.0; b[9] = mfg.1
        b[10] = UInt8(product & 0xFF); b[11] = UInt8((product >> 8) & 0xFF)
        b[12] = UInt8(serial & 0xFF); b[13] = UInt8((serial >> 8) & 0xFF)
        b[14] = UInt8((serial >> 16) & 0xFF); b[15] = UInt8((serial >> 24) & 0xFF)
        b[16] = week; b[17] = year; b[18] = version; b[19] = revision
        b[21] = widthCm; b[22] = heightCm; b[23] = gamma
        // Monitor-name descriptor at offset 54.
        b[54] = 0; b[55] = 0; b[56] = 0; b[57] = 0xFC; b[58] = 0
        let nameBytes = Array(monitorName.utf8).prefix(13)
        for (i, ch) in nameBytes.enumerated() { b[59 + i] = ch }
        if nameBytes.count < 13 { b[59 + nameBytes.count] = 0x0A }   // newline terminator
        // Detailed-timing descriptor at offset 72.
        if let t = timing {
            b[72] = 0x01; b[73] = 0x01   // non-zero pixel clock → detailed timing, not a display descriptor
            b[74] = UInt8(t.h & 0xFF)
            b[76] = UInt8((t.h >> 8) << 4)
            b[77] = UInt8(t.v & 0xFF)
            b[79] = UInt8((t.v >> 8) << 4)
        }
        b[126] = extensions
        let sum = b[0..<127].reduce(0) { $0 + Int($1) }
        b[127] = UInt8((256 - (sum % 256)) % 256)
        if !validChecksum { b[127] = b[127] &+ 1 }
        return b
    }

    func testParsesAllBaseFields() {
        let edid = EDID.parse(makeEDID())
        XCTAssertNotNil(edid)
        XCTAssertEqual(edid?.manufacturerID, "SAM")
        XCTAssertEqual(edid?.productCode, 0x1234)
        XCTAssertEqual(edid?.serialNumber, 0x0A0B0C0D)
        XCTAssertEqual(edid?.manufactureWeek, 10)
        XCTAssertEqual(edid?.manufactureYear, 2023)
        XCTAssertEqual(edid?.edidVersion, 1)
        XCTAssertEqual(edid?.edidRevision, 4)
        XCTAssertEqual(edid?.widthCm, 75)
        XCTAssertEqual(edid?.heightCm, 32)
        XCTAssertEqual(edid?.gamma ?? 0, 2.2, accuracy: 0.001)
        XCTAssertEqual(edid?.extensionCount, 0)
        XCTAssertEqual(edid?.checksumValid, true)
    }

    func testManufacturerIDDecodesThreeLetters() {
        // "DEL": D=4, E=5, L=12 → (4<<10)|(5<<5)|12 = 0x10AC
        let edid = EDID.parse(makeEDID(mfg: (0x10, 0xAC)))
        XCTAssertEqual(edid?.manufacturerID, "DEL")
    }

    func testParsesMonitorNameAndTimingDescriptors() {
        let edid = EDID.parse(makeEDID(monitorName: "S34J55x", timing: (3440, 1440)))
        XCTAssertEqual(edid?.monitorName, "S34J55x")
        XCTAssertEqual(edid?.preferredResolution?.width, 3440)
        XCTAssertEqual(edid?.preferredResolution?.height, 1440)
    }

    func testSerialTextDescriptor() {
        var bytes = makeEDID(monitorName: "Mon")
        // Turn the offset-72 descriptor into a 0xFF serial-text descriptor.
        for i in 72..<90 { bytes[i] = 0 }
        bytes[75] = 0xFF
        let serial = "H4ZN12345"
        for (i, ch) in Array(serial.utf8).enumerated() { bytes[77 + i] = ch }
        bytes[77 + serial.utf8.count] = 0x0A
        // fix checksum
        let sum = bytes[0..<127].reduce(0) { $0 + Int($1) }
        bytes[127] = UInt8((256 - (sum % 256)) % 256)
        XCTAssertEqual(EDID.parse(bytes)?.serialText, "H4ZN12345")
    }

    func testRejectsBadHeaderAndShortBlocks() {
        var bad = makeEDID(); bad[0] = 0x01
        XCTAssertNil(EDID.parse(bad))
        XCTAssertNil(EDID.parse([UInt8](repeating: 0, count: 64)))
        XCTAssertNil(EDID.parse([]))
    }

    func testInvalidChecksumStillParsesButFlags() {
        let edid = EDID.parse(makeEDID(validChecksum: false))
        XCTAssertNotNil(edid)                       // tolerant: still parses
        XCTAssertEqual(edid?.checksumValid, false)  // but flags the bad checksum
    }

    func testExtensionCount() {
        XCTAssertEqual(EDID.parse(makeEDID(extensions: 1))?.extensionCount, 1)
    }

    func testStableHashIsDeterministicAndDistinct() {
        let a = makeEDID(serial: 0x1111_1111)
        let b = makeEDID(serial: 0x2222_2222)
        XCTAssertEqual(EDID.stableHash(a), EDID.stableHash(a))   // deterministic
        XCTAssertNotEqual(EDID.stableHash(a), EDID.stableHash(b))
        XCTAssertEqual(EDID.stableHash(a).count, 16)
    }

    func testCodableRoundTrips() throws {
        let edid = EDID.parse(makeEDID())!
        let data = try JSONEncoder().encode(edid)
        XCTAssertEqual(try JSONDecoder().decode(EDID.self, from: data), edid)
    }
}
