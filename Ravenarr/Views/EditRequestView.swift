import SwiftUI

/// Mirrors the web UI's "Edit Request" modal — lets an admin re-route a
/// request to a different Radarr/Sonarr server, quality profile, or root
/// folder (e.g. a "Kids" library vs. the standard one).
struct EditRequestView: View {
    @EnvironmentObject var appState: AppState
    let request: MediaRequest
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var servers: [ServiceServerSummary] = []
    @State private var selectedServerId: Int?
    @State private var profiles: [ServiceProfile] = []
    @State private var rootFolders: [ServiceRootFolder] = []
    @State private var selectedProfileId: Int?
    @State private var selectedRootFolder: String?

    @State private var isLoadingServers = false
    @State private var isLoadingDetails = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var mediaType: MediaType { request.media?.mediaType ?? .movie }
    private var serviceName: String { mediaType == .tv ? "Sonarr" : "Radarr" }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section(serviceName) {
                    if isLoadingServers {
                        ProgressView()
                    } else if servers.isEmpty {
                        Text("No \(serviceName) servers configured on this Seerr instance.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        Picker("Server", selection: $selectedServerId) {
                            ForEach(servers) { server in
                                Text(server.name).tag(Optional(server.id))
                            }
                        }
                    }
                }

                Section("Quality Profile") {
                    if isLoadingDetails {
                        ProgressView()
                    } else if profiles.isEmpty {
                        Text("Pick a server first.").foregroundStyle(.secondary).font(.footnote)
                    } else {
                        Picker("Profile", selection: $selectedProfileId) {
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                    }
                }

                Section("Root Folder") {
                    if isLoadingDetails {
                        ProgressView()
                    } else if rootFolders.isEmpty {
                        Text("Pick a server first.").foregroundStyle(.secondary).font(.footnote)
                    } else {
                        Picker("Folder", selection: $selectedRootFolder) {
                            ForEach(rootFolders) { folder in
                                Text(folder.path).tag(Optional(folder.path))
                            }
                        }
                    }
                }
            }
            .seerrBackground()
            .navigationTitle("Edit Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || selectedServerId == nil || selectedProfileId == nil || selectedRootFolder == nil)
                }
            }
            .task { await loadServers() }
            .onChange(of: selectedServerId) { _, newValue in
                guard let newValue else { return }
                Task { await loadDetails(serverId: newValue) }
            }
        }
    }

    private func loadServers() async {
        guard let client = appState.apiClient else { return }
        isLoadingServers = true
        defer { isLoadingServers = false }
        do {
            servers = mediaType == .tv ? try await client.sonarrServers() : try await client.radarrServers()
            selectedServerId = request.serverId ?? servers.first(where: { $0.isDefault == true })?.id ?? servers.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetails(serverId: Int) async {
        guard let client = appState.apiClient else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            let details = mediaType == .tv
                ? try await client.sonarrServiceDetails(serverId: serverId)
                : try await client.radarrServiceDetails(serverId: serverId)
            profiles = details.profiles
            rootFolders = details.rootFolders
            selectedProfileId = request.profileId ?? profiles.first?.id
            selectedRootFolder = request.rootFolder ?? rootFolders.first?.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let client = appState.apiClient,
              let serverId = selectedServerId,
              let profileId = selectedProfileId,
              let rootFolder = selectedRootFolder else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.updateRequestSettings(
                requestID: request.id,
                mediaType: mediaType,
                serverId: serverId,
                profileId: profileId,
                rootFolder: rootFolder
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
