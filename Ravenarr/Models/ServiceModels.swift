import Foundation

/// A configured Radarr or Sonarr server, as listed by /api/v1/service/{radarr,sonarr}.
/// A Seerr instance can have several (e.g. one for movies, one 4K, one "kids").
struct ServiceServerSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let isDefault: Bool?
    let is4k: Bool?
}

struct ServiceProfile: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct ServiceRootFolder: Decodable, Identifiable, Hashable {
    let id: Int
    let path: String
}

/// Response from /api/v1/service/{radarr,sonarr}/{serverId} — the live list of
/// quality profiles and root folders (e.g. "/movies" vs "/movies-kids") that
/// server actually has configured, fetched from Radarr/Sonarr itself.
struct ServiceDetails: Decodable {
    let profiles: [ServiceProfile]
    let rootFolders: [ServiceRootFolder]
}

/// Body for PUT /api/v1/request/{id} — re-routes an existing request to a
/// different server/profile/root folder (e.g. Kids vs. standard library).
struct UpdateRequestBody: Encodable {
    let mediaType: MediaType
    let serverId: Int
    let profileId: Int
    let rootFolder: String
}
