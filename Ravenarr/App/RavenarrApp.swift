import SwiftUI

@main
struct RavenarrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        SeerrTheme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .tint(SeerrTheme.accent)
                .preferredColorScheme(.dark)
        }
    }
}
