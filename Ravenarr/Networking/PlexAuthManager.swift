import Foundation
import AuthenticationServices
import UIKit

/// Drives Plex's PIN-based sign-in: request a PIN, send the user to
/// app.plex.tv to approve it, poll until Plex attaches an auth token,
/// then hand that token to whichever Seerr server the caller specifies.
///
/// This step never talks to your Seerr server — it's pure Plex.tv, which
/// is exactly why the same flow works no matter which server URL the
/// user entered during onboarding.
@MainActor
final class PlexAuthManager: NSObject {

    private let clientIdentifier = PlexClientIdentifier.current
    private let productName = "Seerr Client"
    private var webSession: ASWebAuthenticationSession?

    private var commonHeaders: [String: String] {
        [
            "Accept": "application/json",
            "X-Plex-Product": productName,
            "X-Plex-Client-Identifier": clientIdentifier
        ]
    }

    /// Runs the full flow end-to-end and returns a Plex auth token.
    func signIn() async throws -> String {
        let pin = try await requestPin()
        try await presentAuthSheet(code: pin.code)
        return try await pollForToken(pinID: pin.id)
    }

    // MARK: - Step 1: request a PIN

    private func requestPin() async throws -> PlexPin {
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins?strong=true")!)
        request.httpMethod = "POST"
        commonHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    // MARK: - Step 2: present the Plex login page

    private func presentAuthSheet(code: String) async throws {
        var components = URLComponents(string: "https://app.plex.tv/auth")!
        components.fragment = "?clientID=\(clientIdentifier)&code=\(code)&context[device][product]=\(productName)"
        guard let authURL = components.url else {
            throw PlexAuthError(message: "Could not build Plex auth URL")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // callbackURLScheme is never actually invoked — Plex's page has no
            // redirect step for this flow. We dismiss the session ourselves
            // once polling (below) detects the PIN was approved.
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "seerrclient") { _, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    // Expected: we cancel it programmatically on success.
                    return
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session

            guard session.start() else {
                continuation.resume(throwing: PlexAuthError(message: "Could not present Plex sign-in"))
                return
            }
            continuation.resume()
        }
    }

    // MARK: - Step 3: poll until the PIN is claimed

    private func pollForToken(pinID: Int) async throws -> String {
        let url = URL(string: "https://plex.tv/api/v2/pins/\(pinID)")!
        let deadline = Date().addingTimeInterval(120) // give up after 2 minutes

        while Date() < deadline {
            var request = URLRequest(url: url)
            commonHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response, data: data)
            let pin = try JSONDecoder().decode(PlexPin.self, from: data)

            if let token = pin.authToken, !token.isEmpty {
                webSession?.cancel()
                webSession = nil
                return token
            }
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s between polls
        }

        webSession?.cancel()
        throw PlexAuthError(message: "Plex sign-in timed out. Please try again.")
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PlexAuthError(message: "Plex.tv returned an unexpected response")
        }
    }
}

extension PlexAuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
