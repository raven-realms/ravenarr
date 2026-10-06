import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var serverStore = ServerStore()
    @Published var currentUser: SeerrUser?
    @Published var isCheckingSession = true
    @Published var lastError: String?

    private(set) var apiClient: SeerrAPIClient?

    var isSignedIn: Bool { currentUser != nil }
    var hasServer: Bool { serverStore.activeServer != nil }

    init() {
        rebuildClient()
    }

    /// Call after adding/switching servers so the API client points at the right one.
    func rebuildClient() {
        guard let server = serverStore.activeServer else {
            apiClient = nil
            currentUser = nil
            isCheckingSession = false
            return
        }
        let client = SeerrAPIClient(server: server)
        apiClient = client
        Task { await restoreSessionIfPossible(client: client) }
    }

    private func restoreSessionIfPossible(client: SeerrAPIClient) async {
        isCheckingSession = true
        defer { isCheckingSession = false }

        guard client.isAuthenticated else {
            currentUser = nil
            return
        }
        do {
            currentUser = try await client.fetchCurrentUser()
        } catch {
            // Stored cookie is stale/expired — fall back to the sign-in screen.
            currentUser = nil
        }
    }

    func addServer(url: URL, nickname: String, kind: SeerrKind, allowSelfSignedCertificate: Bool = false) {
        let config = ServerConfig(baseURL: url, nickname: nickname, serverKind: kind, allowSelfSignedCertificate: allowSelfSignedCertificate)
        serverStore.add(config)
        rebuildClient()
    }

    /// Switch to an already-saved server without going back through onboarding.
    func switchServer(to server: ServerConfig) {
        guard server.id != serverStore.activeServerID else { return }
        serverStore.activeServerID = server.id
        rebuildClient()
    }

    func completeSignIn(plexToken: String) async {
        await completeSignIn { try await $0.authenticateWithPlex(plexToken: plexToken) }
    }

    func completeJellyfinSignIn(username: String, password: String) async {
        await completeSignIn { try await $0.authenticateWithJellyfin(username: username, password: password) }
    }

    func completeLocalSignIn(email: String, password: String) async {
        await completeSignIn { try await $0.authenticateLocal(email: email, password: password) }
    }

    private func completeSignIn(_ authenticate: (SeerrAPIClient) async throws -> SeerrUser) async {
        guard let apiClient else { return }
        do {
            currentUser = try await authenticate(apiClient)
            lastError = nil
            await registerPushTokenIfPossible()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Updates the active server's push-relay URL and immediately tries to
    /// register this device with it, if we already have a token + user.
    func setPushRelayURL(_ url: URL?) {
        guard var server = serverStore.activeServer else { return }
        server.pushRelayURL = url
        serverStore.update(server)
        Task { await registerPushTokenIfPossible() }
    }

    /// No-ops silently if any piece (relay URL, device token, signed-in user) is
    /// missing yet — this gets called opportunistically from multiple places.
    func registerPushTokenIfPossible() async {
        guard let server = serverStore.activeServer,
              let relayURL = server.pushRelayURL,
              let token = PushNotificationManager.shared.deviceToken,
              let user = currentUser else { return }
        do {
            try await PushRelayClient.registerDevice(
                relayURL: relayURL,
                deviceToken: token,
                seerrUserId: user.id,
                seerrServerURL: server.baseURL
            )
        } catch {
            lastError = "Couldn't register for push notifications: \(error.localizedDescription)"
        }
    }

    func signOut() {
        guard let apiClient else { return }
        Task {
            await apiClient.signOut()
            currentUser = nil
        }
    }
}
