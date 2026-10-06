import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject var appState: AppState
    let item: MediaResult

    @State private var isRequesting = false
    @State private var requestErrorMessage: String?
    @State private var requestSucceeded = false
    @State private var showRequestOptions = false
    @State private var collection: CollectionSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: item.posterURL) { image in
                    image.resizable().aspectRatio(2/3, contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.2))
                }
                .frame(maxWidth: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)

                Text(item.displayTitle)
                    .font(.title2.bold())

                if let date = item.displayDate {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let overview = item.overview {
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
            guard item.mediaType == .movie else { return }
            collection = try? await appState.apiClient?.movieCollection(tmdbId: item.id)
        }
    }

    @ViewBuilder
    private var requestSection: some View {
        if let status = item.mediaInfo?.status, status != .unknown {
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
