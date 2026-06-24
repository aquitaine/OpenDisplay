import XCTest
@testable import DisplayDomain

final class FavoriteResolutionsTests: XCTestCase {
    private func mode(_ pw: Int, _ ph: Int, hz: Double = 60, hiDPI: Bool = false) -> DisplayMode {
        DisplayMode(pixelWidth: pw, pixelHeight: ph, pointWidth: pw, pointHeight: ph,
                    refreshHz: hz, isHiDPI: hiDPI)
    }
    private let dispA = DisplayRecordID(rawValue: "disp_A")
    private let dispB = DisplayRecordID(rawValue: "disp_B")

    func testKeyEncodesSizeRefreshAndHiDPI() {
        XCTAssertEqual(FavoriteResolutions.key(for: mode(1920, 1080, hz: 60)), "1920x1080@60")
        XCTAssertEqual(FavoriteResolutions.key(for: mode(1920, 1080, hz: 120)), "1920x1080@120")
        XCTAssertEqual(FavoriteResolutions.key(for: mode(1512, 982, hz: 60, hiDPI: true)), "1512x982@60@2x")
    }

    func testToggleAddsAndRemoves() {
        var fav = FavoriteResolutions()
        XCTAssertFalse(fav.isFavorite(mode(1920, 1080), for: dispA))
        fav.toggle(mode(1920, 1080), for: dispA)
        XCTAssertTrue(fav.isFavorite(mode(1920, 1080), for: dispA))
        fav.toggle(mode(1920, 1080), for: dispA)
        XCTAssertFalse(fav.isFavorite(mode(1920, 1080), for: dispA))
    }

    func testNewestFirstOrdering() {
        var fav = FavoriteResolutions()
        fav.add(mode(1280, 720), for: dispA)
        fav.add(mode(1920, 1080), for: dispA)
        fav.add(mode(2560, 1440), for: dispA)
        XCTAssertEqual(fav.favoriteKeys(for: dispA), ["2560x1440@60", "1920x1080@60", "1280x720@60"])
    }

    func testPerDisplayIsolation() {
        var fav = FavoriteResolutions()
        fav.add(mode(1920, 1080), for: dispA)
        XCTAssertTrue(fav.isFavorite(mode(1920, 1080), for: dispA))
        XCTAssertFalse(fav.isFavorite(mode(1920, 1080), for: dispB))
    }

    func testAddRemoveAreIdempotent() {
        var fav = FavoriteResolutions()
        fav.add(mode(1920, 1080), for: dispA)
        fav.add(mode(1920, 1080), for: dispA)   // no-op
        XCTAssertEqual(fav.favoriteKeys(for: dispA).count, 1)
        fav.remove(mode(1280, 720), for: dispA) // not present — no-op
        XCTAssertEqual(fav.favoriteKeys(for: dispA).count, 1)
    }

    func testMergedPutsFavoritesFirstThenStopsDeduped() {
        let stops = [mode(1280, 720), mode(1920, 1080), mode(2560, 1440), mode(3440, 1440)]
        var fav = FavoriteResolutions()
        fav.add(mode(2560, 1440), for: dispA)
        fav.add(mode(1280, 720), for: dispA)   // newest first → 1280 before 2560
        let merged = fav.merged(stops: stops, for: dispA)
        XCTAssertEqual(merged.map { "\($0.pointWidth)" },
                       ["1280", "2560", "1920", "3440"])   // favorites (newest first), then the rest
        // no duplicates
        XCTAssertEqual(merged.count, 4)
    }

    func testMergedDropsStaleFavoritesNotInStops() {
        var fav = FavoriteResolutions()
        fav.add(mode(3840, 2160), for: dispA)   // favorite no longer offered
        fav.add(mode(1920, 1080), for: dispA)
        let stops = [mode(1280, 720), mode(1920, 1080)]
        let merged = fav.merged(stops: stops, for: dispA)
        XCTAssertEqual(merged.map { "\($0.pointWidth)" }, ["1920", "1280"])  // 3840 dropped
    }

    func testMergedWithNoFavoritesEqualsStops() {
        let stops = [mode(1280, 720), mode(1920, 1080)]
        XCTAssertEqual(FavoriteResolutions().merged(stops: stops, for: dispA), stops)
    }

    func testCodableRoundTrips() throws {
        var fav = FavoriteResolutions()
        fav.add(mode(1920, 1080), for: dispA)
        fav.add(mode(2560, 1440, hiDPI: true), for: dispB)
        let data = try JSONEncoder().encode(fav)
        XCTAssertEqual(try JSONDecoder().decode(FavoriteResolutions.self, from: data), fav)
    }
}
