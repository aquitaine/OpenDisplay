import XCTest
@testable import SceneEngine

final class SceneStoreTests: XCTestCase {
    private func scene(_ id: String, _ name: String) -> Scene {
        Scene(id: id, name: name, members: [])
    }

    func testLibrarySaveLookupDelete() async {
        let library = await SceneLibrary(store: InMemorySceneStore())
        await library.save(scene("s1", "Desk"))
        let named = await library.scene(named: "Desk")
        XCTAssertEqual(named?.id, "s1")
        await library.delete(id: "s1")
        let all = await library.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testUpsertByID() async {
        let library = await SceneLibrary(store: InMemorySceneStore())
        await library.save(scene("s1", "Desk"))
        await library.save(scene("s1", "Desk Renamed"))
        let all = await library.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Desk Renamed")
    }

    func testPersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-scene-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = await SceneLibrary(store: DiskSceneStore(directory: directory))
        await first.save(scene("s1", "Desk"))

        let second = await SceneLibrary(store: DiskSceneStore(directory: directory))
        let all = await second.all()
        XCTAssertEqual(all.map(\.id), ["s1"])
    }
}
