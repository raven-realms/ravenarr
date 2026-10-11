import SwiftUI

/// Mirrors the web UI's "Report an Issue" flow. Only shown for media that's
/// already on the server (needs Seerr's internal media id, not just a tmdbId).
struct ReportIssueSheet: View {
    @EnvironmentObject var appState: AppState
    let item: MediaResult
    let mediaId: Int
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var issueType: IssueType = .video
    @State private var message = ""
    @State private var availableSeasons: [Int] = []
    @State private var selectedSeason: Int?
    @State private var episode = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Issue Type") {
                    Picker("Type", selection: $issueType) {
                        ForEach([IssueType.video, .audio, .subtitle, .other], id: \.self) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if item.mediaType == .tv && !availableSeasons.isEmpty {
                    Section("Where") {
                        Picker("Season", selection: $selectedSeason) {
                            Text("Not specific to a season").tag(Int?.none)
                            ForEach(availableSeasons, id: \.self) { season in
                                Text("Season \(season)").tag(Int?.some(season))
                            }
                        }
                        if selectedSeason != nil {
                            TextField("Episode (optional)", text: $episode)
                                .keyboardType(.numberPad)
                        }
                    }
                }

                Section("Describe the problem") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }
            }
            .seerrBackground()
            .navigationTitle("Report an Issue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                guard item.mediaType == .tv, let client = appState.apiClient else { return }
                availableSeasons = (try? await client.tvSeasons(tmdbId: item.id)) ?? []
            }
        }
    }

    private func submit() async {
        guard let client = appState.apiClient else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await client.createIssue(
                mediaId: mediaId,
                issueType: issueType,
                message: message,
                problemSeason: selectedSeason,
                problemEpisode: Int(episode)
            )
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ReportIssueSheet(
        item: MediaResult(id: 1, mediaType: .movie, title: "Preview", name: nil, overview: nil, posterPath: nil, releaseDate: nil, firstAirDate: nil, mediaInfo: nil),
        mediaId: 1,
        onSubmitted: {}
    )
    .environmentObject(AppState())
}
