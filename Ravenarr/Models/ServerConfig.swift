import Foundation

/// A single Seerr (Overseerr/Jellyseerr) server the user has added.
/// Nothing here is hardcoded — `baseURL` is whatever the user types in
/// during onboarding, validated against /api/v1/status before saving.
struct ServerConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var baseURL: URL
    var nickname: String
    var serverKind: SeerrKind
    var apiVersion: String?

    /// Address of a push-relay service you run yourself (receives Seerr's
    /// MEDIA_APPROVED/MEDIA_AVAILABLE webhooks and forwards to APNs).
    /// Not part of Overseerr/Jellyseerr's own API — nil until you set one up.
    var pushRelayURL: URL?

    /// Opt-in only: accepts ANY TLS certificate for this server, including
    /// invalid/self-signed/expired ones. For homelab reverse proxies without
    /// a real CA cert. Off by default — only you can turn this on, and only
    /// for a server you already typed in yourself.
    var allowSelfSignedCertificate: Bool

    init(
        id: UUID = UUID(),
        baseURL: URL,
        nickname: String,
        serverKind: SeerrKind,
        apiVersion: String? = nil,
        pushRelayURL: URL? = nil,
        allowSelfSignedCertificate: Bool = false
    ) {
        self.id = id
        self.baseURL = baseURL
        self.nickname = nickname
        self.serverKind = serverKind
        self.apiVersion = apiVersion
        self.pushRelayURL = pushRelayURL
        self.allowSelfSignedCertificate = allowSelfSignedCertificate
    }

    /// Keychain account key — session tokens are stored per server id,
    /// so switching servers never mixes up credentials.
    var keychainAccount: String { id.uuidString }

    private enum CodingKeys: String, CodingKey {
        case id, baseURL, nickname, serverKind, apiVersion, pushRelayURL, allowSelfSignedCertificate
    }

    /// Custom decode so servers saved before `allowSelfSignedCertificate` existed
    /// still load instead of silently disappearing from UserDefaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        nickname = try container.decode(String.self, forKey: .nickname)
        serverKind = try container.decode(SeerrKind.self, forKey: .serverKind)
        apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion)
        pushRelayURL = try container.decodeIfPresent(URL.self, forKey: .pushRelayURL)
        allowSelfSignedCertificate = try container.decodeIfPresent(Bool.self, forKey: .allowSelfSignedCertificate) ?? false
    }
}

enum SeerrKind: String, Codable {
    case overseerr
    case jellyseerr
    case unknown
}

/// Persists the list of known servers (UserDefaults — non-sensitive) and
/// tracks which one is currently active. Session tokens themselves live
/// in Keychain via KeychainHelper, never here.
@MainActor
final class ServerStore: ObservableObject {
    private static let defaultsKey = "com.seerrclient.savedServers"
    private static let activeServerKey = "com.seerrclient.activeServerID"

    @Published private(set) var servers: [ServerConfig] = []
    @Published var activeServerID: UUID? {
        didSet {
            UserDefaults.standard.set(activeServerID?.uuidString, forKey: Self.activeServerKey)
        }
    }

    var activeServer: ServerConfig? {
        servers.first { $0.id == activeServerID }
    }

    init() {
        load()
    }

    func add(_ server: ServerConfig) {
        servers.append(server)
        activeServerID = server.id
        persist()
    }

    func update(_ server: ServerConfig) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        persist()
    }

    func remove(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        KeychainHelper.delete(service: SeerrAPIClient.sessionKeychainService, account: server.keychainAccount)
        if activeServerID == server.id {
            activeServerID = servers.first?.id
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: Self.activeServerKey) {
            activeServerID = UUID(uuidString: idString)
        }
    }
}
