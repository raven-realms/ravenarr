import Foundation

enum IssueType: Int, Codable, Hashable {
    case video = 1
    case audio = 2
    case subtitle = 3
    case other = 4

    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .subtitle: return "Subtitle"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "speaker.wave.2"
        case .subtitle: return "captions.bubble"
        case .other: return "questionmark.circle"
        }
    }
}

enum IssueStatus: Int, Codable, Hashable {
    case open = 1
    case resolved = 2

    var label: String { self == .open ? "Open" : "Resolved" }
}

struct IssueMedia: Decodable {
    let id: Int
    let tmdbId: Int?
    let mediaType: MediaType
}

struct SeerrIssue: Decodable, Identifiable {
    let id: Int
    let issueType: IssueType
    let status: IssueStatus
    let media: IssueMedia?
    let createdBy: SeerrUser?
    let problemSeason: Int?
    let problemEpisode: Int?
    let createdAt: String?
}

struct IssuesResponse: Decodable {
    let pageInfo: PageInfo
    let results: [SeerrIssue]
}
