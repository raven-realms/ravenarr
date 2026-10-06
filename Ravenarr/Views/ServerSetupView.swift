import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var nickname = ""
    @State private var allowSelfSignedCertificate = false
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the address of your own Overseerr or Jellyseerr server. Nothing is preconfigured — this app works with whatever server you point it at.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Server") {
                    TextField("requests.yourdomain.com", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nickname (optional)", text: $nickname)
                    Toggle("Allow self-signed certificate", isOn: $allowSelfSignedCertificate)
                }

                if allowSelfSignedCertificate {
                    Section {
                        Text("Accepts ANY certificate for this server, including invalid ones. Only turn this on for a server you trust and typed in yourself.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await validateAndAdd() }
                    } label: {
                        if isValidating {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                    }
                    .disabled(urlText.isEmpty || isValidating)
                }
            }
            .seerrBackground()
            .navigationTitle("Add Server")
        }
    }

    private func validateAndAdd() async {
        errorMessage = nil
        isValidating = true
        defer { isValidating = false }

        do {
            let (url, status) = try await SeerrAPIClient.probe(urlString: urlText, allowSelfSignedCertificate: allowSelfSignedCertificate)
            let kind: SeerrKind = status.version.lowercased().contains("jellyseerr") ? .jellyseerr : .overseerr
            let name = nickname.isEmpty ? (url.host ?? "My Server") : nickname
            appState.addServer(url: url, nickname: name, kind: kind, allowSelfSignedCertificate: allowSelfSignedCertificate)
            // Adding a server switches the active one and clears the session, so
            // the app will naturally drop to SignInView for it — dismiss if we're
            // presented as a sheet (adding a 2nd+ server from Profile); a no-op
            // when this is the first-launch root screen.
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ServerSetupView().environmentObject(AppState())
}
