import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @State private var relayURLText = ""
    @State private var relayAPIKeyText = ""
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = appState.currentUser {
                    Section("Signed in as") {
                        Text(user.displayName)
                    }
                }
                if let server = appState.serverStore.activeServer {
                    Section("Server") {
                        Text(server.nickname)
                        Text(server.baseURL.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.serverStore.servers.count > 1 {
                    Section("Switch Server") {
                        ForEach(appState.serverStore.servers) { server in
                            Button {
                                appState.switchServer(to: server)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.nickname).foregroundStyle(.primary)
                                        Text(server.baseURL.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if server.id == appState.serverStore.activeServerID {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
                if let user = appState.currentUser {
                    Section("Role") {
                        Text(user.isAdmin ? "Admin" : (user.canManage ? "Manager" : "User"))
                    }
                }

                Section("Push Notifications") {
                    if pushManager.isAuthorized {
                        Label(
                            pushManager.deviceToken != nil ? "Enabled" : "Enabled (waiting for device token…)",
                            systemImage: "bell.badge.fill"
                        )
                        .foregroundStyle(.green)
                    } else {
                        Button("Enable Push Notifications") {
                            Task { await pushManager.requestAuthorizationAndRegister() }
                        }
                    }

                    TextField("Relay URL (optional)", text: $relayURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Relay API Key (if required)", text: $relayAPIKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Relay Settings") {
                        appState.setPushRelayURL(URL(string: relayURLText))
                        appState.setPushRelayAPIKey(relayAPIKeyText.isEmpty ? nil : relayAPIKeyText)
                    }
                    .disabled(relayURLText.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text("Address of a relay that forwards Seerr's webhook events to Apple Push — your own self-hosted one, or a key you were issued for a hosted service. Leave both blank if you haven't set one up yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appState.serverStore.activeServer?.pushRelayAPIKey != nil {
                        Text("A relay API key is saved for this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = pushManager.registrationError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Add Another Server") {
                        showAddServer = true
                    }
                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                    }
                }
            }
            .seerrBackground()
            .navigationTitle("Profile")
            .onAppear {
                relayURLText = appState.serverStore.activeServer?.pushRelayURL?.absoluteString ?? ""
            }
            .onReceive(pushManager.$deviceToken) { _ in
                Task { await appState.registerPushTokenIfPossible() }
            }
            .sheet(isPresented: $showAddServer) {
                ServerSetupView()
            }
        }
    }
}

#Preview {
    ProfileView().environmentObject(AppState())
}
