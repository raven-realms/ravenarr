import SwiftUI

struct RequestsView: View {
    @EnvironmentObject var appState: AppState
    @State private var requests: [MediaRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: RequestFilter = .pending
    @State private var editingRequest: MediaRequest?
    @StateObject private var detailsStore = MediaDetailsStore()

    enum RequestFilter: String, CaseIterable, Identifiable {
        case pending, all
        var id: String { rawValue }
        var label: String { self == .pending ? "Pending" : "All" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(RequestFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Surfaced on screen now — previously a failed fetch just looked
                // like an empty queue with no indication why.
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                List(requests) { req in
                    RequestRow(
                        request: req,
                        details: detailsStore.details(for: req.media?.tmdbId),
                        canManage: appState.currentUser?.canManage ?? false,
                        onDecision: { approve in Task { await update(req, approve: approve) } },
                        onEdit: { editingRequest = req }
                    )
                    .listRowBackground(SeerrTheme.surface)
                }
                .listStyle(.plain)
                .seerrBackground()
                .overlay {
                    if isLoading && requests.isEmpty {
                        ProgressView()
                    } else if requests.isEmpty && !isLoading {
                        ContentUnavailableView(
                            filter == .pending ? "No Pending Requests" : "No Requests",
                            systemImage: "tray"
                        )
                    }
                }
            }
            .background(SeerrTheme.background.ignoresSafeArea())
            .navigationTitle("Requests")
            .navigationDestination(for: MediaResult.self) { item in
                MediaDetailView(item: item)
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: filter) { _, _ in Task { await load() } }
            .sheet(item: $editingRequest) { req in
                EditRequestView(request: req) {
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.myRequests(filter: filter.rawValue)
            requests = response.results
            errorMessage = nil
            let items = requests.compactMap { req -> (tmdbId: Int, mediaType: MediaType)? in
                guard let media = req.media, let tmdbId = media.tmdbId else { return nil }
                return (tmdbId, media.mediaType)
            }
            await detailsStore.loadMissing(for: items, client: client)
        } catch {
            // Don't silently clear to an empty list without saying why.
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ request: MediaRequest, approve: Bool) async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.updateRequestStatus(requestID: request.id, approve: approve)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RequestRow: View {
    let request: MediaRequest
    let details: MediaDetails?
    let canManage: Bool
    let onDecision: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let tmdbId = request.media?.tmdbId {
                NavigationLink(value: mediaResult(tmdbId: tmdbId)) {
                    posterAndTitle
                }
                .buttonStyle(.plain)
            } else {
                posterAndTitle
            }

            Spacer()

            if canManage {
                HStack(spacing: 16) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil.circle.fill")
                    }
                    .tint(.blue)

                    if request.approvalStatus == .pending {
                        Button { onDecision(true) } label: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .tint(.green)

                        Button { onDecision(false) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .tint(.red)
                    }
                }
                .buttonStyle(.plain)
                .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var posterAndTitle: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: details?.posterURL) { image in
                image.resizable().aspectRatio(2 / 3, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: request.media?.mediaType == .tv ? "tv" : "film")
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(details?.displayTitle ?? (request.media?.mediaType.rawValue.capitalized ?? "Request"))
                    .font(.headline)
                    .foregroundStyle(.white)

                Label(request.approvalStatus.label, systemImage: request.approvalStatus.icon)
                    .font(.subheadline)
                    .foregroundStyle(color(for: request.approvalStatus))

                if let requestedBy = request.requestedBy?.displayName {
                    Text("Requested by \(requestedBy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func mediaResult(tmdbId: Int) -> MediaResult {
        MediaResult(
            id: tmdbId,
            mediaType: request.media?.mediaType ?? .movie,
            title: details?.title,
            name: details?.name,
            overview: details?.overview,
            posterPath: details?.posterPath,
            releaseDate: details?.releaseDate,
            firstAirDate: details?.firstAirDate,
            mediaInfo: nil
        )
    }

    private func color(for status: RequestApprovalStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .declined: return .red
        }
    }
}

#Preview {
    RequestsView().environmentObject(AppState())
}
