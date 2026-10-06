import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.hasServer {
                ServerSetupView()
            } else if appState.isCheckingSession {
                ProgressView("Checking session…")
            } else if !appState.isSignedIn {
                SignInView()
            } else {
                MainTabView()
            }
        }
        .background(SeerrTheme.background.ignoresSafeArea())
        .animation(.default, value: appState.hasServer)
        .animation(.default, value: appState.isSignedIn)
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            RequestsView()
                .tabItem { Label("Requests", systemImage: "list.bullet.rectangle") }
            IssuesView()
                .tabItem { Label("Issues", systemImage: "exclamationmark.triangle") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
