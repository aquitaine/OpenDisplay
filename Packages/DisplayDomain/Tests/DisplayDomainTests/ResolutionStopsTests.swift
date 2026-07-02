import XCTest
@testable import DisplayDomain

final class ResolutionStopsTests: XCTestCase {
    private func mode(_ pw: Int, _ ph: Int, hz: Double = 60, hiDPI: Bool = false) -> DisplayMode {
        // Pixel size mirrors HiDPI doubling; the helper only reads point-size/refresh/HiDPI.
        DisplayMode(pixelWidth: pw * (hiDPI ? 2 : 1), pixelHeight: ph * (hiDPI ? 2 : 1),
                    pointWidth: pw, pointHeight: ph, refreshHz: hz, isHiDPI: hiDPI)
    }

    func testOneStopPerPointSizeAscendingByArea() {
        let modes = [mode(2560, 1440), mode(1280, 720), mode(1920, 1080)]
        let stops = ResolutionStops.areaSorted(from: modes)
        XCTAssertEqual(stops.map { [$0.pointWidth, $0.pointHeight] },
                       [[1280, 720], [1920, 1080], [2560, 1440]])
    }

    func testDeduplicatesPointSizePreferringHiDPIThenRefresh() {
        let modes = [
            mode(1920, 1080, hz: 60, hiDPI: false),
            mode(1920, 1080, hz: 120, hiDPI: false),
            mode(1920, 1080, hz: 60, hiDPI: true),   // HiDPI should win over higher refresh
        ]
        let stops = ResolutionStops.areaSorted(from: modes)
        XCTAssertEqual(stops.count, 1)
        XCTAssertTrue(stops[0].isHiDPI)
    }

    func testPrefersHighestRefreshWhenNoHiDPIVariant() {
        let modes = [mode(1920, 1080, hz: 60), mode(1920, 1080, hz: 144), mode(1920, 1080, hz: 120)]
        let stops = ResolutionStops.areaSorted(from: modes)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].refreshHz, 144)
    }

    func testEqualAreaDifferentAspectOrdersDeterministically() {
        // 1600x900 and 1200x1200 both have... different areas; use a true equal-area tie:
        // 1920x1000 (1.92M) vs 1600x1200 (1.92M) — same area, deterministic by width then height.
        let modes = [mode(1600, 1200), mode(1920, 1000)]
        let a = ResolutionStops.areaSorted(from: modes)
        let b = ResolutionStops.areaSorted(from: modes.reversed())
        XCTAssertEqual(a, b, "ordering must be independent of input order")
        XCTAssertEqual(a.map(\.pointWidth), [1600, 1920])  // equal area → ascending width
    }

    func testIndexMatchesByPointSizeRegardlessOfVariant() {
        let stops = ResolutionStops.areaSorted(from: [mode(1280, 720), mode(1920, 1080), mode(2560, 1440)])
        // A current mode at 1920x1080 but a different refresh/HiDPI variant still maps to its stop.
        let current = mode(1920, 1080, hz: 120, hiDPI: true)
        XCTAssertEqual(ResolutionStops.index(of: current, in: stops), 1)
    }

    func testIndexNilWhenAbsent() {
        let stops = ResolutionStops.areaSorted(from: [mode(1280, 720), mode(1920, 1080)])
        XCTAssertNil(ResolutionStops.index(of: mode(3840, 2160), in: stops))
    }

    func testEmptyAndSingleModeInputs() {
        XCTAssertTrue(ResolutionStops.areaSorted(from: []).isEmpty)
        let single = ResolutionStops.areaSorted(from: [mode(1920, 1080)])
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(ResolutionStops.index(of: mode(1920, 1080), in: single), 0)
    }

    func testStopsAreStrictlyMonotonicInArea() {
        let modes = [mode(800, 600), mode(1024, 768), mode(1280, 800), mode(2560, 1600), mode(1920, 1200)]
        let stops = ResolutionStops.areaSorted(from: modes)
        let areas = stops.map { $0.pointWidth * $0.pointHeight }
        XCTAssertEqual(areas, areas.sorted())
        XCTAssertEqual(Set(areas).count, areas.count, "distinct areas remain distinct and ordered")
    }
}
