import SwiftUI

/// Replaces the old Plex-only login screen. Overseerr is Plex-only, but
/// Jellyseerr can be backed by Jellyfin/Emby instead, and either server can
/// have "Local Login" enabled — so this always offers all three and lets the
/// server tell us (via a normal error) if a method doesn't apply.
struct SignInView: View {
    @EnvironmentObject var appState: AppState

    private enum Method: String, CaseIterable, Identifiable {
        case plex = "Plex"
        case jellyfin = "Jellyfin/Emby"
        case local = "Local"
        var id: String { rawValue }
    }

    @State private var method: Method = .plex
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let plexAuthManager = PlexAuthManager()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "play.tv.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            if let server = appState.serverStore.activeServer {
                Text("Sign in to \(server.nickname)")
                    .font(.title2.bold())
                Text(server.baseURL.host ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Method", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if method != .plex {
                VStack(spacing: 12) {
                    TextField(method == .local ? "Email" : "Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text(method == .plex ? "Sign in with Plex" : "Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSigningIn || (method != .plex && (username.isEmpty || password.isEmpty)))
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeerrTheme.background.ignoresSafeArea())
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            switch method {
            case .plex:
                let plexToken = try await plexAuthManager.signIn()
                await appState.completeSignIn(plexToken: plexToken)
            case .jellyfin:
                await appState.completeJellyfinSignIn(username: username, password: password)
            case .local:
                await appState.completeLocalSignIn(email: username, password: password)
            }
            if let lastError = appState.lastError {
                errorMessage = lastError
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SignInView().environmentObject(AppState())
}
