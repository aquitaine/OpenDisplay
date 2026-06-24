import DisplayDomain
import Foundation

/// Atomic, on-disk store for `FavoriteResolutions` (Batch-2 #3), alongside the other Application
/// Support state. Pure Foundation, so it's exercised by `make test`; a missing or unreadable file
/// degrades to empty favourites rather than failing.
public struct FavoritesStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("favorites.json")
    }

    /// Returns persisted favourites, or empty when the file is absent or corrupt.
    public func load() -> FavoriteResolutions {
        guard let data = try? Data(contentsOf: fileURL),
              let favorites = try? JSONDecoder().decode(FavoriteResolutions.self, from: data) else {
            return FavoriteResolutions()
        }
        return favorites
    }

    public func save(_ favorites: FavoriteResolutions) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(favorites).write(to: fileURL, options: .atomic)
    }
}
