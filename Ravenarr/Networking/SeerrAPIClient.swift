import Foundation

enum SeerrAPIError: LocalizedError {
    case invalidServerURL
    case notASeerrServer
    case notAuthenticated
    case server(status: Int, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "That doesn't look like a valid server URL."
        case .notASeerrServer: return "Couldn't find an Overseerr/Jellyseerr API at that address."
        case .notAuthenticated: return "You're not signed in to this server."
        case .server(let status, let message): return message ?? "Server returned an error (\(status))."
        case .decoding: return "Received an unexpected response from the server."
        }
    }
}

/// One instance per active server. Holds the session cookie in memory
/// (backed by Keychain, keyed per-server) so requests survive across
/// launches without ever hardcoding a server address.
final class SeerrAPIClient {
    static let sessionKeychainService = "com.seerrclient.session"

    private let server: ServerConfig
    private let session: URLSession
    private var sessionCookie: String? {
        didSet {
            guard let sessionCookie else {
                KeychainHelper.delete(service: Self.sessionKeychainService, account: server.keychainAccount)
                return
            }
            KeychainHelper.saveString(sessionCookie, service: Self.sessionKeychainService, account: server.keychainAccount)
        }
    }

    var isAuthenticated: Bool { sessionCookie != nil }

    init(server: ServerConfig) {
        self.server = server
        self.session = Self.makeSession(allowSelfSignedCertificate: server.allowSelfSignedCertificate)
        self.sessionCookie = KeychainHelper.readString(service: Self.sessionKeychainService, account: server.keychainAccount)
    }

    private static func makeSession(allowSelfSignedCertificate: Bool) -> URLSession {
        guard allowSelfSignedCertificate else { return .shared }
        return URLSession(configuration: .default, delegate: InsecureTrustDelegate(), delegateQueue: nil)
    }

    // MARK: - Onboarding: validate an arbitrary server URL

    /// Hits /api/v1/status (unauthenticated) to confirm this is really a
    /// Seerr instance before the user commits to saving it.
    static func probe(urlString: String, allowSelfSignedCertificate: Bool = false) async throws -> (url: URL, status: SeerrStatus) {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") { normalized = "https://" + normalized }
        guard let base = URL(string: normalized) else { throw SeerrAPIError.invalidServerURL }

        let statusURL = base.appendingPathComponent("api/v1/status")
        var request = URLRequest(url: statusURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let probeSession = makeSession(allowSelfSignedCertificate: allowSelfSignedCertificate)
        let (data, response) = try await probeSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SeerrAPIError.notASeerrServer
        }
        do {
            let status = try JSONDecoder().decode(SeerrStatus.self, from: data)
            return (base, status)
        } catch {
            throw SeerrAPIError.notASeerrServer
        }
    }

    // MARK: - Auth

    /// Shared by every auth method below: POST credentials, pull the session
    /// cookie off Set-Cookie, decode the signed-in user.
    private func performAuth<B: Encodable>(path: String, body: B) async throws -> SeerrUser {
        let (data, response) = try await rawRequest(path: path, method: "POST", body: body, attachSession: false)
        if let http = response as? HTTPURLResponse,
           let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
            // Keep only the connect.sid= pair; drop attributes like Path/HttpOnly.
            sessionCookie = setCookie.split(separator: ";").first.map(String.init)
        }
        return try decode(SeerrUser.self, from: data, response: response)
    }

    /// Exchanges a Plex auth token (from PlexAuthManager) for a session
    /// cookie on THIS server. Nothing about this call is server-specific
    /// beyond the base URL — the same Plex token works on any Seerr
    /// instance the user's Plex account has access to.
    @discardableResult
    func authenticateWithPlex(plexToken: String) async throws -> SeerrUser {
        struct Body: Encodable { let authToken: String }
        return try await performAuth(path: "api/v1/auth/plex", body: Body(authToken: plexToken))
    }

    /// Jellyseerr servers backed by Jellyfin/Emby instead of Plex.
    @discardableResult
    func authenticateWithJellyfin(username: String, password: String) async throws -> SeerrUser {
        struct Body: Encodable { let username: String; let password: String }
        return try await performAuth(path: "api/v1/auth/jellyfin", body: Body(username: username, password: password))
    }

    /// Overseerr/Jellyseerr's own local accounts (not tied to Plex/Jellyfin at all),
    /// only usable if the server admin enabled "Local Login".
    @discardableResult
    func authenticateLocal(email: String, password: String) async throws -> SeerrUser {
        struct Body: Encodable { let email: String; let password: String }
        return try await performAuth(path: "api/v1/auth/local", body: Body(email: email, password: password))
    }

    func fetchCurrentUser() async throws -> SeerrUser {
        try await request(path: "api/v1/auth/me", method: "GET")
    }

    func signOut() async {
        _ = try? await rawRequest(path: "api/v1/auth/logout", method: "POST", body: Optional<String>.none)
        sessionCookie = nil
    }

    // MARK: - Discover / search

    func discoverMovies(page: Int = 1) async throws -> SearchResponse {
        try await request(path: "api/v1/discover/movies", query: ["page": "\(page)"])
    }

    func discoverTV(page: Int = 1) async throws -> SearchResponse {
        try await request(path: "api/v1/discover/tv", query: ["page": "\(page)"])
    }

    func search(query: String, page: Int = 1) async throws -> SearchResponse {
        try await request(path: "api/v1/search", query: ["query": query, "page": "\(page)"])
    }

    /// Overseerr's own sync of the signed-in Plex account's watchlist — not
    /// available for Jellyfin/local accounts, so callers should hide this
    /// section rather than show an error when it comes back empty.
    func discoverWatchlist(page: Int = 1) async throws -> SearchResponse {
        try await request(path: "api/v1/discover/watchlist", query: ["page": "\(page)"])
    }

    /// Season numbers available for a TV show (excludes season 0/specials).
    func tvSeasons(tmdbId: Int) async throws -> [Int] {
        let details: TVDetails = try await request(path: "api/v1/tv/\(tmdbId)")
        return details.seasons.map(\.seasonNumber).filter { $0 > 0 }.sorted()
    }

    /// Whether a 4K-capable Radarr/Sonarr server is configured, so the UI can
    /// decide whether to even show a 4K toggle on the request sheet.
    func has4KOption(mediaType: MediaType) async throws -> Bool {
        let servers = mediaType == .tv ? try await sonarrServers() : try await radarrServers()
        return servers.contains { $0.is4k == true }
    }

    /// nil if the movie isn't part of a collection.
    func movieCollection(tmdbId: Int) async throws -> CollectionSummary? {
        let details: MovieDetails = try await request(path: "api/v1/movie/\(tmdbId)")
        return details.collection
    }

    func collectionDetails(id: Int) async throws -> CollectionDetails {
        try await request(path: "api/v1/collection/\(id)")
    }

    /// Requests/issues only carry `tmdbId` — fetch the full title/poster/overview
    /// for display, same as the web UI does per request card. Also used by the
    /// detail screen for rating + availability status.
    func mediaDetails(tmdbId: Int, mediaType: MediaType) async throws -> MediaDetails {
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        return try await request(path: path)
    }

    /// "More like this" row on the detail screen, same as the web UI.
    func recommendations(tmdbId: Int, mediaType: MediaType) async throws -> [RelatedMediaItem] {
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)/recommendations" : "api/v1/movie/\(tmdbId)/recommendations"
        let page: RelatedMediaPage = try await request(path: path)
        return page.results
    }

    // MARK: - Requests

    /// `filter` is Seerr's own request-list filter: "pending" | "all" | "approved" | "processing" | ...
    /// Regular users only ever get requests they made; admins/managers get everyone's.
    /// Note: unlike /discover and /search (which use TMDB-style `page`), this endpoint
    /// validates its query strictly and only accepts `skip`/`take` for pagination.
    func myRequests(filter: String = "pending", take: Int = 50, skip: Int = 0) async throws -> RequestsResponse {
        try await request(path: "api/v1/request", query: ["filter": filter, "sort": "added", "take": "\(take)", "skip": "\(skip)"])
    }

    @discardableResult
    func createRequest(mediaType: MediaType, mediaId: Int, seasons: [Int]? = nil, is4k: Bool = false) async throws -> MediaRequest {
        let body = NewRequestBody(mediaType: mediaType, mediaId: mediaId, seasons: seasons, is4k: is4k)
        return try await request(path: "api/v1/request", method: "POST", body: body)
    }

    /// Approve/decline — requires the signed-in Plex user to have manage-requests permission on the server.
    func updateRequestStatus(requestID: Int, approve: Bool) async throws {
        let action = approve ? "approve" : "decline"
        _ = try await rawRequest(path: "api/v1/request/\(requestID)/\(action)", method: "POST", body: Optional<String>.none)
    }

    /// Re-routes an existing request's server/profile/root folder — e.g. sending
    /// a movie to a "Kids" Radarr root folder instead of the default one.
    /// Mirrors the web UI's request edit modal.
    @discardableResult
    func updateRequestSettings(requestID: Int, mediaType: MediaType, serverId: Int, profileId: Int, rootFolder: String) async throws -> MediaRequest {
        let body = UpdateRequestBody(mediaType: mediaType, serverId: serverId, profileId: profileId, rootFolder: rootFolder)
        return try await request(path: "api/v1/request/\(requestID)", method: "PUT", body: body)
    }

    func radarrServers() async throws -> [ServiceServerSummary] {
        try await request(path: "api/v1/service/radarr")
    }

    func sonarrServers() async throws -> [ServiceServerSummary] {
        try await request(path: "api/v1/service/sonarr")
    }

    func radarrServiceDetails(serverId: Int) async throws -> ServiceDetails {
        try await request(path: "api/v1/service/radarr/\(serverId)")
    }

    func sonarrServiceDetails(serverId: Int) async throws -> ServiceDetails {
        try await request(path: "api/v1/service/sonarr/\(serverId)")
    }

    // MARK: - Issues

    /// `filter`: "open" | "resolved" | "all". Regular users see only issues they reported;
    /// admins/managers see everyone's — same visibility rule as requests.
    /// Same `skip`/`take` pagination as /request, not TMDB-style `page`.
    func issues(filter: String = "open", take: Int = 50, skip: Int = 0) async throws -> IssuesResponse {
        try await request(path: "api/v1/issue", query: ["filter": filter, "sort": "added", "take": "\(take)", "skip": "\(skip)"])
    }

    /// NOTE: mirrors the request approve/decline route shape (`POST /request/:id/:action`).
    /// Verify against your server if this 404s — issue status routes are less consistently
    /// documented than request ones across Overseerr/Jellyseerr versions.
    func updateIssueStatus(issueID: Int, resolve: Bool) async throws {
        let action = resolve ? "resolved" : "open"
        _ = try await rawRequest(path: "api/v1/issue/\(issueID)/\(action)", method: "POST", body: Optional<String>.none)
    }

    // MARK: - Generic request helpers

    private func request<T: Decodable>(path: String, method: String = "GET", query: [String: String] = [:]) async throws -> T {
        let (data, response) = try await rawRequest(path: path, method: method, query: query, body: Optional<String>.none)
        return try decode(T.self, from: data, response: response)
    }

    private func request<T: Decodable, B: Encodable>(path: String, method: String = "GET", body: B) async throws -> T {
        let (data, response) = try await rawRequest(path: path, method: method, body: body)
        return try decode(T.self, from: data, response: response)
    }

    private func rawRequest<B: Encodable>(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: B?,
        attachSession: Bool = true
    ) async throws -> (Data, URLResponse) {
        var components = URLComponents(url: server.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw SeerrAPIError.invalidServerURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if attachSession {
            guard let sessionCookie else { throw SeerrAPIError.notAuthenticated }
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        if let body, !(body is String) {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            sessionCookie = nil
            throw SeerrAPIError.notAuthenticated
        }
        return (data, response)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8)
            throw SeerrAPIError.server(status: status, message: message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SeerrAPIError.decoding(error)
        }
    }
}
