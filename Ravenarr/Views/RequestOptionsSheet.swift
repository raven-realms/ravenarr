import SwiftUI

/// Shown before submitting a request so TV shows get a season picker and
/// either media type can opt into 4K — mirrors the web UI's request modal,
/// which previously wasn't exposed here at all (every TV request silently
/// grabbed the whole series, and 4K was never offered).
struct RequestOptionsSheet: View {
    @EnvironmentObject var appState: AppState
    let item: MediaResult
    let onSubmit: (_ seasons: [Int]?, _ is4k: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var availableSeasons: [Int] = []
    @State private var selectedSeasons: Set<Int> = []
    @State private var has4KOption = false
    @State private var is4k = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                if item.mediaType == .tv {
                    Section("Seasons") {
                        if isLoading {
                            ProgressView()
                        } else if availableSeasons.isEmpty {
                            Text("Couldn't load season list — requesting all seasons.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(selectedSeasons.count == availableSeasons.count ? "Deselect All" : "Select All") {
                                if selectedSeasons.count == availableSeasons.count {
                                    selectedSeasons.removeAll()
                                } else {
                                    selectedSeasons = Set(availableSeasons)
                                }
                            }
                            ForEach(availableSeasons, id: \.self) { season in
                                Button {
                                    toggle(season)
                                } label: {
                                    HStack {
                                        Text("Season \(season)").foregroundStyle(.primary)
                                        Spacer()
                                        if selectedSeasons.contains(season) {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if has4KOption {
                    Section {
                        Toggle("Request in 4K", isOn: $is4k)
                    }
                }
            }
            .seerrBackground()
            .navigationTitle("Request \(item.displayTitle)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Request") {
                        let seasons = item.mediaType == .tv ? Array(selectedSeasons).sorted() : nil
                        onSubmit(seasons, is4k)
                    }
                    .disabled(isLoading || (item.mediaType == .tv && !availableSeasons.isEmpty && selectedSeasons.isEmpty))
                }
            }
            .task { await load() }
        }
    }

    private func toggle(_ season: Int) {
        if selectedSeasons.contains(season) {
            selectedSeasons.remove(season)
        } else {
            selectedSeasons.insert(season)
        }
    }

    private func load() async {
        guard let client = appState.apiClient else { return }
        defer { isLoading = false }
        do {
            if item.mediaType == .tv {
                availableSeasons = try await client.tvSeasons(tmdbId: item.id)
                selectedSeasons = Set(availableSeasons)
            }
            has4KOption = try await client.has4KOption(mediaType: item.mediaType)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RequestOptionsSheet(
        item: MediaResult(id: 1, mediaType: .tv, title: nil, name: "Preview Show", overview: nil, posterPath: nil, releaseDate: nil, firstAirDate: nil, mediaInfo: nil),
        onSubmit: { _, _ in }
    )
    .environmentObject(AppState())
}
