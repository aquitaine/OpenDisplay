import XCTest
@testable import DisplayDomain

final class OSDContentTests: XCTestCase {
    func testValueClamps() {
        XCTAssertEqual(OSDContent(kind: .brightness, value: 2).value, 1)
        XCTAssertEqual(OSDContent(kind: .brightness, value: -1).value, 0)
        XCTAssertEqual(OSDContent(kind: .volume, value: 0.5).value, 0.5, accuracy: 1e-6)
    }

    func testFilledSegments() {
        XCTAssertEqual(OSDContent(kind: .brightness, value: 0).filledSegments, 0)
        XCTAssertEqual(OSDContent(kind: .brightness, value: 1).filledSegments, 16)
        XCTAssertEqual(OSDContent(kind: .brightness, value: 0.5).filledSegments, 8)
        // 0.97 * 16 = 15.52 → rounds to 16; clamp keeps it in range.
        XCTAssertEqual(OSDContent(kind: .brightness, value: 0.97).filledSegments, 16)
        XCTAssertEqual(OSDContent(kind: .brightness, value: 2).filledSegments, 16)
    }

    func testPercent() {
        XCTAssertEqual(OSDContent(kind: .volume, value: 0.5).percent, 50)
        XCTAssertEqual(OSDContent(kind: .volume, value: 0.336).percent, 34)
    }

    func testGlyphs() {
        XCTAssertEqual(OSDContent(kind: .brightness, value: 0.5).glyph, "sun.max")
        XCTAssertEqual(OSDContent(kind: .mute, value: 0.5).glyph, "speaker.slash")
        XCTAssertEqual(OSDContent(kind: .volume, value: 0).glyph, "speaker.slash")
        XCTAssertEqual(OSDContent(kind: .volume, value: 0.2).glyph, "speaker.wave.1")
        XCTAssertEqual(OSDContent(kind: .volume, value: 0.8).glyph, "speaker.wave.2")
        XCTAssertEqual(OSDContent(kind: .input, value: 0).glyph, "arrow.triangle.swap")
    }

    func testInputKindCarriesALabel() {
        let content = OSDContent(kind: .input, value: 0, label: "HDMI 2")
        XCTAssertEqual(content.label, "HDMI 2")
        XCTAssertNil(OSDContent(kind: .brightness, value: 0.5).label)
    }
}
