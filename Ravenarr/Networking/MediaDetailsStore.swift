import Foundation

/// Fetches and caches title/poster/overview for (tmdbId, mediaType) pairs, keyed
/// by tmdbId. Shared by RequestsView and IssuesView since both only get a bare
/// tmdbId back from their list endpoints.
@MainActor
final class MediaDetailsStore: ObservableObject {
    @Published private(set) var cache: [Int: MediaDetails] = [:]

    func details(for tmdbId: Int?) -> MediaDetails? {
        guard let tmdbId else { return nil }
        return cache[tmdbId]
    }

    func loadMissing(for items: [(tmdbId: Int, mediaType: MediaType)], client: SeerrAPIClient) async {
        var seen = Set<Int>()
        let missing = items.filter { seen.insert($0.tmdbId).inserted && cache[$0.tmdbId] == nil }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: (Int, MediaDetails?).self) { group in
            for item in missing {
                group.addTask {
                    let result = try? await client.mediaDetails(tmdbId: item.tmdbId, mediaType: item.mediaType)
                    return (item.tmdbId, result)
                }
            }
            for await (tmdbId, result) in group {
                if let result {
                    cache[tmdbId] = result
                }
            }
        }
    }
}
