import Foundation

// MARK: - Status

struct SeerrStatus: Decodable {
    let version: String
    let updateAvailable: Bool?
}

// MARK: - Auth

struct SeerrUser: Decodable, Identifiable {
    let id: Int
    let email: String?
    let username: String?
    let plexUsername: String?
    let avatar: String?
    let permissions: Int?

    var displayName: String {
        plexUsername ?? username ?? email ?? "User \(id)"
    }

    /// Overseerr/Jellyseerr permission bitmask: ADMIN = 2, MANAGE_REQUESTS = 16, MANAGE_ISSUES = 8192.
    var isAdmin: Bool {
        guard let permissions else { return false }
        return permissions & 2 != 0
    }

    var canManage: Bool {
        guard let permissions else { return false }
        return permissions & 2 != 0 || permissions & 16 != 0 || permissions & 8192 != 0
    }
}

// MARK: - Media / search

enum MediaType: String, Codable, Hashable {
    case movie
    case tv
    case person
}

struct MediaResult: Decodable, Identifiable {
    let id: Int
    let mediaType: MediaType
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaInfo: MediaInfo?

    var displayTitle: String { title ?? name ?? "Untitled" }
    var displayDate: String? { releaseDate ?? firstAirDate }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }
}

struct MediaInfo: Decodable {
    /// Seerr's own internal media row id — NOT the TMDB id. Required to
    /// report an issue (POST /api/v1/issue wants this, not tmdbId). Only
    /// present once the title has actually been requested/is on the server,
    /// which is also exactly when reporting an issue makes sense.
    let id: Int?
    let status: RequestStatus?
    let requests: [MediaRequest]?
}

/// A trailer/clip/etc. from TMDB, passed through by Seerr's `relatedVideos`.
struct RelatedVideo: Decodable {
    let key: String
    let site: String
    let type: String
    let name: String
}

/// Requests/issues only store `tmdbId` + `mediaType` locally — title, poster,
/// and overview come from a separate `/movie/{id}` or `/tv/{id}` lookup.
/// Deliberately doesn't decode `mediaType` — the single-item detail endpoints
/// don't reliably include it since it's implicit in which path you called.
struct MediaDetails: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    /// TMDB's 0-10 average rating. Shown on the detail screen, same as the web UI.
    let voteAverage: Double?
    let mediaInfo: MediaInfo?

    /// Movie-only: content certification (PG-13, R, ...) by country.
    let releases: MovieReleases?
    /// TV-only: content rating (TV-14, TV-MA, ...) by country.
    let contentRatings: TVContentRatings?

    let relatedVideos: [RelatedVideo]?

    var displayTitle: String { title ?? name ?? "Untitled" }
    var displayDate: String? { releaseDate ?? firstAirDate }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    /// First YouTube trailer, same as the web UI's "Watch Trailer" button.
    var trailerURL: URL? {
        guard let key = relatedVideos?.first(where: { $0.site == "YouTube" && $0.type == "Trailer" })?.key else {
            return nil
        }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    /// US parental-guidance rating (PG-13, TV-MA, etc.) — distinct from
    /// `voteAverage`, which is TMDB's 0-10 popularity score, not a content
    /// rating. nil if TMDB has no US rating on file for this title.
    var certification: String? {
        if let movieCert = releases?.results
            .first(where: { $0.iso31661 == "US" })?
            .releaseDates
            .first(where: { !$0.certification.isEmpty })?
            .certification {
            return movieCert
        }
        if let tvRating = contentRatings?.results
            .first(where: { $0.iso31661 == "US" })?
            .rating,
            !tvRating.isEmpty {
            return tvRating
        }
        return nil
    }
}

struct MovieReleaseDate: Decodable {
    let certification: String
}

struct MovieReleaseCountry: Decodable {
    let iso31661: String
    let releaseDates: [MovieReleaseDate]

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct MovieReleases: Decodable {
    let results: [MovieReleaseCountry]
}

struct TVContentRatingCountry: Decodable {
    let iso31661: String
    let rating: String

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case rating
    }
}

struct TVContentRatings: Decodable {
    let results: [TVContentRatingCountry]
}

/// Lighter than `MediaResult` on purpose: /movie|tv/{id}/recommendations
/// doesn't include `mediaType` (it's implicit — a movie's recommendations
/// are always movies), so this can't reuse MediaResult's non-optional field.
struct RelatedMediaItem: Decodable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?

    var displayTitle: String { title ?? name ?? "Untitled" }
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }
}

struct RelatedMediaPage: Decodable {
    let results: [RelatedMediaItem]
}

struct TVSeasonSummary: Decodable {
    let seasonNumber: Int
}

struct TVDetails: Decodable {
    let seasons: [TVSeasonSummary]
}

struct CollectionSummary: Decodable {
    let id: Int
    let name: String
    let posterPath: String?
}

struct MovieDetails: Decodable {
    let collection: CollectionSummary?
}

/// Deliberately lighter than `MediaResult` — a collection's `parts` list from
/// /api/v1/collection/{id} doesn't reliably include `mediaType` (every part is
/// implicitly a movie), and MediaResult requires it non-optional.
struct CollectionPart: Decodable, Identifiable {
    let id: Int
    let title: String?
    let posterPath: String?
    let mediaInfo: MediaInfo?

    var displayTitle: String { title ?? "Untitled" }
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }
}

struct CollectionDetails: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let parts: [CollectionPart]
}

struct SearchResponse: Decodable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [MediaResult]
}

// MARK: - Requests

/// Mirrors Seerr's numeric media/request status enum.
enum RequestStatus: Int, Codable, Hashable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .partiallyAvailable: return "Partially Available"
        case .available: return "Available"
        }
    }
}

/// The request's own approval status — distinct from `RequestStatus`, which is
/// the underlying media's *availability* on the server. A request can be
/// `.pending` approval while its media is still `.unknown`.
enum RequestApprovalStatus: Int, Codable, Hashable {
    case pending = 1
    case approved = 2
    case declined = 3

    var label: String {
        switch self {
        case .pending: return "Pending Approval"
        case .approved: return "Approved"
        case .declined: return "Declined"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        }
    }
}

struct MediaRequest: Decodable, Identifiable {
    let id: Int
    let status: Int
    let media: RequestedMedia?
    let requestedBy: SeerrUser?
    let createdAt: String?
    let serverId: Int?
    let profileId: Int?
    let rootFolder: String?

    var approvalStatus: RequestApprovalStatus {
        RequestApprovalStatus(rawValue: status) ?? .pending
    }
}

struct RequestedMedia: Decodable {
    let id: Int
    let tmdbId: Int?
    let mediaType: MediaType
    let status: RequestStatus
}

struct RequestsResponse: Decodable {
    let pageInfo: PageInfo
    let results: [MediaRequest]
}

struct PageInfo: Decodable {
    let pages: Int
    let pageSize: Int
    let results: Int
    let page: Int
}

/// Body for POST /api/v1/request
struct NewRequestBody: Encodable {
    let mediaType: MediaType
    let mediaId: Int
    let seasons: [Int]?
    let is4k: Bool?
}
