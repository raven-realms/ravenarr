import Foundation

/// Response from POST https://plex.tv/api/v2/pins
struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id, code
        case authToken
    }
}

/// A unique per-install client identifier Plex requires on every request.
/// Generated once and persisted so this "device" stays recognizable to Plex.
enum PlexClientIdentifier {
    private static let key = "com.seerrclient.plexClientIdentifier"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

struct PlexAuthError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
