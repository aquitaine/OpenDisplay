@testable import TopologyCore
import XCTest

final class BrightnessMonitorTests: XCTestCase {
    func testInitialSampleDoesNotSyncButExternalChangesDo() {
        var monitor = BrightnessMonitor()
        XCTAssertFalse(monitor.observe(0.5, revision: 0))
        XCTAssertFalse(monitor.observe(0.502, revision: 0))
        XCTAssertTrue(monitor.observe(0.6, revision: 0))
        XCTAssertFalse(monitor.observe(0.6, revision: 0))
        XCTAssertTrue(monitor.observe(0.4, revision: 0))
    }

    func testOwnWritesAndOverlappingReadsDoNotEcho() {
        var monitor = BrightnessMonitor()
        XCTAssertFalse(monitor.observe(0.5, revision: 0))
        let beforeWrite = monitor.revision
        monitor.beginWrite()
        XCTAssertFalse(monitor.observe(0.55, revision: monitor.revision))
        let duringWrite = monitor.revision
        monitor.endWrite(value: 0.601)
        XCTAssertFalse(monitor.observe(0.5, revision: beforeWrite))
        XCTAssertFalse(monitor.observe(0.55, revision: duringWrite))
        XCTAssertFalse(monitor.observe(0.601, revision: monitor.revision))
        XCTAssertTrue(monitor.observe(0.7, revision: monitor.revision))
    }

    func testFailedReadbackSeedsNextSampleWithoutSyncing() {
        var monitor = BrightnessMonitor()
        monitor.beginWrite()
        monitor.endWrite(value: nil)
        XCTAssertFalse(monitor.observe(0.5, revision: monitor.revision))
        XCTAssertTrue(monitor.observe(0.6, revision: monitor.revision))
    }

    func testInvalidReadingsDoNotChangeBaseline() {
        var monitor = BrightnessMonitor()
        XCTAssertFalse(monitor.observe(0.5, revision: 0))
        for sample: Float in [.nan, .infinity, -1, 2] {
            XCTAssertFalse(monitor.observe(sample, revision: 0))
        }
        XCTAssertFalse(monitor.observe(0.5, revision: 0))
    }
}
