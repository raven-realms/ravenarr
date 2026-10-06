import Foundation

/// Talks to a push-relay service YOU host — not part of Overseerr/Jellyseerr.
///
/// Seerr has no notion of APNs. The flow is:
///   1. Each signed-in user, on their own phone, gets an APNs device token and
///      POSTs it here. This isn't admin-only — every family member who wants
///      push registers their own token under their own Plex/Seerr account.
///   2. Your relay stores (seerrServerURL, seerrUserEmail) -> [deviceToken, ...].
///      ONE-TO-MANY: a user with two phones registers two tokens; treat this
///      as "add if missing," never "replace," or the older device goes silent.
///   3. In Seerr's admin settings, add a Webhook notification agent pointed at
///      your relay, enabled for "Request Approved" and "Media Available".
///   4. Matching is by EMAIL, not a numeric id — Overseerr's webhook template
///      has no raw internal user id, only `{{notifyuser_email}}` /
///      `{{notifyuser_username}}` / `{{notifyuser_avatar}}`. For those two
///      event types specifically, `notifyuser` is the ORIGINAL REQUESTER, not
///      the admin who approved it — confirmed against Overseerr's own docs.
///      Your relay looks up every token stored for that email and sends each
///      an APNs push using your .p8 key.
///
/// Expected request body for registration (adjust to match your relay):
///   POST {relayURL}/devices
///   { "deviceToken": "<hex>", "seerrUserEmail": "user@example.com", "seerrServerURL": "https://...", "platform": "ios" }
enum PushRelayClient {
    struct RegisterDeviceBody: Encodable {
        let deviceToken: String
        let seerrUserEmail: String
        let seerrServerURL: String
        let platform = "ios"
    }

    static func registerDevice(relayURL: URL, apiKey: String?, deviceToken: String, seerrUserEmail: String, seerrServerURL: URL) async throws {
        var request = URLRequest(url: relayURL.appendingPathComponent("devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            RegisterDeviceBody(deviceToken: deviceToken, seerrUserEmail: seerrUserEmail, seerrServerURL: seerrServerURL.absoluteString)
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
