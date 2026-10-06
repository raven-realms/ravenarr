import Foundation

/// Talks to a push-relay service YOU host — not part of Overseerr/Jellyseerr.
///
/// Seerr has no notion of APNs. The flow is:
///   1. Each signed-in user, on their own phone, gets an APNs device token and
///      POSTs it here. This isn't admin-only — every family member who wants
///      push registers their own token under their own Plex/Seerr account.
///   2. Your relay stores (seerrServerURL, seerrUserId) -> [deviceToken, ...].
///      ONE-TO-MANY: a user with two phones registers two tokens; treat this
///      as "add if missing," never "replace," or the older device goes silent.
///   3. In Seerr's admin settings, add a Webhook notification agent pointed at
///      your relay, enabled for "Request Approved" and "Media Available".
///   4. For those two event types, Seerr's webhook payload's `notifyuser.id`
///      is the ORIGINAL REQUESTER, not the admin who approved it. Your relay
///      looks up every token stored for that `notifyuser.id` and sends each
///      an APNs push using your .p8 key — so the person who asked for the
///      movie is who gets notified, not whoever approved it.
///
/// Expected request body for registration (adjust to match your relay):
///   POST {relayURL}/devices
///   { "deviceToken": "<hex>", "seerrUserId": 2, "seerrServerURL": "https://...", "platform": "ios" }
enum PushRelayClient {
    struct RegisterDeviceBody: Encodable {
        let deviceToken: String
        let seerrUserId: Int
        let seerrServerURL: String
        let platform = "ios"
    }

    static func registerDevice(relayURL: URL, deviceToken: String, seerrUserId: Int, seerrServerURL: URL) async throws {
        var request = URLRequest(url: relayURL.appendingPathComponent("devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RegisterDeviceBody(deviceToken: deviceToken, seerrUserId: seerrUserId, seerrServerURL: seerrServerURL.absoluteString)
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
