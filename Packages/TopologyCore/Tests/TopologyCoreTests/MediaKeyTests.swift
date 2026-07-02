import XCTest
@testable import TopologyCore

final class MediaKeyTests: XCTestCase {
    func testNXKeyTypeMapping() {
        XCTAssertEqual(MediaKeyAction.from(nxKeyType: NXKeyType.brightnessUp), .brightnessUp)
        XCTAssertEqual(MediaKeyAction.from(nxKeyType: NXKeyType.brightnessDown), .brightnessDown)
        XCTAssertEqual(MediaKeyAction.from(nxKeyType: NXKeyType.soundUp), .volumeUp)
        XCTAssertEqual(MediaKeyAction.from(nxKeyType: NXKeyType.soundDown), .volumeDown)
        XCTAssertEqual(MediaKeyAction.from(nxKeyType: NXKeyType.mute), .muteToggle)
    }

    func testUnknownNXKeyTypeIsNil() {
        XCTAssertNil(MediaKeyAction.from(nxKeyType: 99))
        XCTAssertNil(MediaKeyAction.from(nxKeyType: -1))
    }

    func testVolumeVsBrightnessClassification() {
        XCTAssertTrue(MediaKeyAction.volumeUp.isVolume)
        XCTAssertTrue(MediaKeyAction.muteToggle.isVolume)
        XCTAssertTrue(MediaKeyAction.brightnessUp.isBrightness)
        XCTAssertFalse(MediaKeyAction.brightnessDown.isVolume)
    }

    func testSign() {
        XCTAssertEqual(MediaKeyAction.brightnessUp.sign, 1)
        XCTAssertEqual(MediaKeyAction.volumeDown.sign, -1)
        XCTAssertEqual(MediaKeyAction.muteToggle.sign, 0)
    }

    func testSignedDeltaCoarseAndFine() {
        XCTAssertEqual(MediaKeyAction.brightnessUp.signedDelta(fineStep: false), 1.0 / 16.0, accuracy: 1e-6)
        XCTAssertEqual(MediaKeyAction.brightnessUp.signedDelta(fineStep: true), 1.0 / 64.0, accuracy: 1e-6)
        XCTAssertEqual(MediaKeyAction.volumeDown.signedDelta(fineStep: false), -1.0 / 16.0, accuracy: 1e-6)
        XCTAssertEqual(MediaKeyAction.muteToggle.signedDelta(fineStep: false), 0, accuracy: 1e-6)
    }
}
