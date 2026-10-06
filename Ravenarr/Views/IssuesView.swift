import SwiftUI

struct IssuesView: View {
    @EnvironmentObject var appState: AppState
    @State private var issues: [SeerrIssue] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: IssueFilter = .open
    @StateObject private var detailsStore = MediaDetailsStore()

    enum IssueFilter: String, CaseIterable, Identifiable {
        case open, resolved, all
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(IssueFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                List(issues) { issue in
                    IssueRow(
                        issue: issue,
                        details: detailsStore.details(for: issue.media?.tmdbId),
                        canManage: appState.currentUser?.canManage ?? false,
                        onDecision: { resolve in Task { await update(issue, resolve: resolve) } }
                    )
                    .listRowBackground(SeerrTheme.surface)
                }
                .listStyle(.plain)
                .seerrBackground()
                .overlay {
                    if isLoading && issues.isEmpty {
                        ProgressView()
                    } else if issues.isEmpty && !isLoading {
                        ContentUnavailableView("No Issues", systemImage: "checkmark.seal")
                    }
                }
            }
            .background(SeerrTheme.background.ignoresSafeArea())
            .navigationTitle("Issues")
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: filter) { _, _ in Task { await load() } }
        }
    }

    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.issues(filter: filter.rawValue)
            issues = response.results
            errorMessage = nil
            let items = issues.compactMap { issue -> (tmdbId: Int, mediaType: MediaType)? in
                guard let media = issue.media, let tmdbId = media.tmdbId else { return nil }
                return (tmdbId, media.mediaType)
            }
            await detailsStore.loadMissing(for: items, client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ issue: SeerrIssue, resolve: Bool) async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.updateIssueStatus(issueID: issue.id, resolve: resolve)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IssueRow: View {
    let issue: SeerrIssue
    let details: MediaDetails?
    let canManage: Bool
    let onDecision: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: details?.posterURL) { image in
                image.resizable().aspectRatio(2 / 3, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: issue.media?.mediaType == .tv ? "tv" : "film")
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 46, height: 69)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                if let details {
                    Text(details.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Label(issue.issueType.label, systemImage: issue.issueType.icon)
                    .font(details == nil ? .headline : .subheadline)
                    .foregroundStyle(details == nil ? .white : .secondary)

                Text(issue.status.label)
                    .font(.subheadline)
                    .foregroundStyle(issue.status == .open ? .orange : .green)

                if let season = issue.problemSeason {
                    Text("Season \(season)" + (issue.problemEpisode.map { " · Episode \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reporter = issue.createdBy?.displayName {
                    Text("Reported by \(reporter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if canManage {
                Button {
                    onDecision(issue.status == .open)
                } label: {
                    Image(systemName: issue.status == .open ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                }
                .tint(issue.status == .open ? .green : .orange)
                .buttonStyle(.plain)
                .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    IssuesView().environmentObject(AppState())
}
