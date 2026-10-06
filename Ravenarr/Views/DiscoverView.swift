import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @State private var movies: [MediaResult] = []
    @State private var tvShows: [MediaResult] = []
    @State private var watchlist: [MediaResult] = []
    @State private var searchResults: [MediaResult] = []
    @State private var searchQuery = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var isShowingSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding()
                }

                if isShowingSearch {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(searchResults) { item in
                            NavigationLink(value: item) {
                                PosterCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        row(title: "Your Plex Watchlist", items: watchlist)
                        row(title: "Trending Movies", items: movies)
                        row(title: "Trending TV", items: tvShows)
                    }
                    .padding(.vertical)
                }
            }
            .seerrBackground()
            .navigationTitle("Discover")
            .navigationDestination(for: MediaResult.self) { item in
                MediaDetailView(item: item)
            }
            .searchable(text: $searchQuery, prompt: "Movies, shows...")
            .onChange(of: searchQuery) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await search(newValue)
                }
            }
            .refreshable { await load() }
            .task { if movies.isEmpty { await load() } }
            .overlay {
                if isShowingSearch {
                    if isSearching && searchResults.isEmpty {
                        ProgressView()
                    } else if searchResults.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                    }
                } else if isLoading && movies.isEmpty && tvShows.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    @ViewBuilder
    private func row(title: String, items: [MediaResult]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }

        var errors: [String] = []

        do {
            let response = try await client.discoverMovies()
            movies = response.results.filter { $0.mediaType == .movie }
        } catch {
            errors.append("Movies: \(error.localizedDescription)")
        }

        do {
            let response = try await client.discoverTV()
            tvShows = response.results.filter { $0.mediaType == .tv }
        } catch {
            errors.append("TV: \(error.localizedDescription)")
        }

        do {
            let response = try await client.discoverWatchlist()
            watchlist = response.results
        } catch {
            // Plex-only and legitimately unavailable for Jellyfin/local accounts
            // or anyone without a Plex watchlist set up — not a real error, just
            // hide the row.
            watchlist = []
        }

        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func search(_ text: String) async {
        guard let client = appState.apiClient else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await client.search(query: trimmed)
            searchResults = response.results.filter { $0.mediaType != .person }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PosterCell: View {
    let item: MediaResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: item.posterURL) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)).aspectRatio(2/3, contentMode: .fit)
            }
            .frame(width: 110, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.displayTitle)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 110, alignment: .leading)
        }
    }
}

// MediaResult needs Hashable for navigationDestination(for:) — keep it lightweight.
extension MediaResult: Hashable {
    static func == (lhs: MediaResult, rhs: MediaResult) -> Bool { lhs.id == rhs.id && lhs.mediaType == rhs.mediaType }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mediaType)
    }
}

#Preview {
    DiscoverView().environmentObject(AppState())
}
