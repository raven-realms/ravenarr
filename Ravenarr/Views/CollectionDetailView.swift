import SwiftUI

struct CollectionDetailView: View {
    @EnvironmentObject var appState: AppState
    let collectionId: Int

    @State private var details: CollectionDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRequestingAll = false
    @State private var requestedPartIds: Set<Int> = []

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }

            if let details {
                VStack(alignment: .leading, spacing: 16) {
                    if let overview = details.overview {
                        Text(overview).font(.body).padding(.horizontal)
                    }

                    Button {
                        Task { await requestAll() }
                    } label: {
                        if isRequestingAll {
                            ProgressView()
                        } else {
                            Text("Request All Unrequested Movies")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequestingAll || unrequestedParts(in: details).isEmpty)
                    .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(details.parts) { part in
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: part.posterURL) { image in
                                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)).aspectRatio(2/3, contentMode: .fit)
                                }
                                .frame(width: 110, height: 165)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(part.displayTitle)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(width: 110, alignment: .leading)

                                if requestedPartIds.contains(part.id) || (part.mediaInfo?.status != nil && part.mediaInfo?.status != .unknown) {
                                    Label("Requested", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .seerrBackground()
        .navigationTitle(details?.name ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await load() }
    }

    private func unrequestedParts(in details: CollectionDetails) -> [CollectionPart] {
        details.parts.filter { part in
            !requestedPartIds.contains(part.id) && (part.mediaInfo?.status == nil || part.mediaInfo?.status == .unknown)
        }
    }

    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            details = try await client.collectionDetails(id: collectionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestAll() async {
        guard let client = appState.apiClient, let details else { return }
        isRequestingAll = true
        defer { isRequestingAll = false }
        for part in unrequestedParts(in: details) {
            do {
                _ = try await client.createRequest(mediaType: .movie, mediaId: part.id)
                requestedPartIds.insert(part.id)
            } catch {
                errorMessage = "\(part.displayTitle): \(error.localizedDescription)"
                // Keep going — one failed request (e.g. already requested by
                // someone else mid-loop) shouldn't block the rest of the collection.
            }
        }
    }
}

#Preview {
    CollectionDetailView(collectionId: 1).environmentObject(AppState())
}
