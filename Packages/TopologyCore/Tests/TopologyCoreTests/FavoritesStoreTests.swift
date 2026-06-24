import XCTest
import DisplayDomain
@testable import TopologyCore

final class FavoritesStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-favorites-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func mode(_ pw: Int, _ ph: Int) -> DisplayMode {
        DisplayMode(pixelWidth: pw, pixelHeight: ph, pointWidth: pw, pointHeight: ph, refreshHz: 60, isHiDPI: false)
    }

    func testLoadReturnsEmptyWhenAbsent() {
        XCTAssertEqual(FavoritesStore(directory: directory).load(), FavoriteResolutions())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = FavoritesStore(directory: directory)
        var fav = FavoriteResolutions()
        fav.add(mode(2560, 1440), for: DisplayRecordID(rawValue: "disp_X"))
        try store.save(fav)
        XCTAssertEqual(store.load(), fav)
        XCTAssertTrue(store.load().isFavorite(mode(2560, 1440), for: DisplayRecordID(rawValue: "disp_X")))
    }

    func testCorruptFileFallsBackToEmpty() throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("favorites.json"))
        XCTAssertEqual(FavoritesStore(directory: directory).load(), FavoriteResolutions())
    }
}
