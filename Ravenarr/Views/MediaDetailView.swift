import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject var appState: AppState
    let item: MediaResult

    @State private var details: MediaDetails?
    @State private var recommendations: [RelatedMediaItem] = []
    @State private var isRequesting = false
    @State private var requestErrorMessage: String?
    @State private var requestSucceeded = false
    @State private var showRequestOptions = false
    @State private var collection: CollectionSummary?

    /// Prefer the freshly-fetched details once they land; `item` is just the
    /// instantly-available placeholder (from Discover/search, or a bare
    /// tmdbId+mediaType pair from Requests/Issues).
    private var posterURL: URL? { details?.posterURL ?? item.posterURL }
    private var displayTitle: String { details?.displayTitle ?? item.displayTitle }
    private var displayDate: String? { details?.displayDate ?? item.displayDate }
    private var overview: String? { details?.overview ?? item.overview }
    private var status: RequestStatus? {
        let status = details?.mediaInfo?.status ?? item.mediaInfo?.status
        return (status == .unknown) ? nil : status
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: posterURL) { image in
                    image.resizable().aspectRatio(2/3, contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.2))
                }
                .frame(maxWidth: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)

                Text(displayTitle)
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    if let date = displayDate {
                        Text(date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let rating = details?.voteAverage, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                    }
                }

                if let overview {
                    Text(overview)
                        .font(.body)
                }

                if let collection {
                    NavigationLink(value: collection) {
                        Label("Part of \(collection.name) — view collection", systemImage: "square.stack")
                    }
                    .padding(.top, 4)
                }

                requestSection

                if !recommendations.isEmpty {
                    recommendationsSection
                }
            }
            .padding()
        }
        .seerrBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CollectionSummary.self) { summary in
            CollectionDetailView(collectionId: summary.id)
        }
        .sheet(isPresented: $showRequestOptions) {
            RequestOptionsSheet(item: item) { seasons, is4k in
                showRequestOptions = false
                Task { await sendRequest(seasons: seasons, is4k: is4k) }
            }
        }
        .task {
            await loadDetails()
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(recommendations) { related in
                        NavigationLink(value: mediaResult(for: related)) {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: related.posterURL) { image in
                                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)).aspectRatio(2/3, contentMode: .fit)
                                }
                                .frame(width: 110, height: 165)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(related.displayTitle)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    /// A recommended item is always the same media type as the thing you're
    /// looking at — the endpoint doesn't say so explicitly, so we supply it.
    private func mediaResult(for related: RelatedMediaItem) -> MediaResult {
        MediaResult(
            id: related.id,
            mediaType: item.mediaType,
            title: related.title,
            name: related.name,
            overview: related.overview,
            posterPath: related.posterPath,
            releaseDate: related.releaseDate,
            firstAirDate: related.firstAirDate,
            mediaInfo: nil
        )
    }

    @ViewBuilder
    private var requestSection: some View {
        if let status {
            Label(status.label, systemImage: iconForStatus(status))
                .padding(.top, 8)
        } else if requestSucceeded {
            Label("Requested", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 8)
        } else {
            Button {
                showRequestOptions = true
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("Request")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            .padding(.top, 8)

            if let requestErrorMessage {
                Text(requestErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func iconForStatus(_ status: RequestStatus) -> String {
        switch status {
        case .available: return "checkmark.circle.fill"
        case .partiallyAvailable: return "circle.lefthalf.filled"
        case .processing: return "arrow.triangle.2.circlepath"
        case .pending: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func fetchDetails(client: SeerrAPIClient) async -> MediaDetails? {
        try? await client.mediaDetails(tmdbId: item.id, mediaType: item.mediaType)
    }

    private func fetchRecommendations(client: SeerrAPIClient) async -> [RelatedMediaItem] {
        (try? await client.recommendations(tmdbId: item.id, mediaType: item.mediaType)) ?? []
    }

    private func fetchCollection(client: SeerrAPIClient) async -> CollectionSummary? {
        guard item.mediaType == .movie else { return nil }
        return try? await client.movieCollection(tmdbId: item.id)
    }

    private func loadDetails() async {
        guard let client = appState.apiClient else { return }
        async let detailsResult = fetchDetails(client: client)
        async let recommendationsResult = fetchRecommendations(client: client)
        async let collectionResult = fetchCollection(client: client)
        details = await detailsResult
        recommendations = await recommendationsResult
        collection = await collectionResult
    }

    private func sendRequest(seasons: [Int]?, is4k: Bool) async {
        guard let client = appState.apiClient else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await client.createRequest(mediaType: item.mediaType, mediaId: item.id, seasons: seasons, is4k: is4k)
            requestSucceeded = true
            requestErrorMessage = nil
        } catch {
            requestErrorMessage = error.localizedDescription
        }
    }
}

extension CollectionSummary: Hashable {
    static func == (lhs: CollectionSummary, rhs: CollectionSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    MediaDetailView(item: MediaResult(id: 1, mediaType: .movie, title: "Preview", name: nil, overview: nil, posterPath: nil, releaseDate: nil, firstAirDate: nil, mediaInfo: nil))
        .environmentObject(AppState())
}
