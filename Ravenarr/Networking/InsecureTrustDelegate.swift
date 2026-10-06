import Foundation

/// Accepts ANY TLS certificate — self-signed, expired, wrong hostname, all of it.
/// Only ever used when `ServerConfig.allowSelfSignedCertificate` is true, which is
/// an explicit opt-in for a server address the user typed in themselves. This is a
/// real security tradeoff (no protection against a MITM on that connection) that's
/// acceptable for a homelab reverse proxy without a real CA cert, not a default.
final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
