import SwiftUI
import UIKit

/// Seerr's own dark indigo/purple look, applied app-wide. No hardcoded
/// server-specific styling here — just brand colors.
enum SeerrTheme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.098)   // ~#0E0E19
    static let surface = Color(red: 0.106, green: 0.098, blue: 0.169)      // ~#1B192B
    static let accent = Color(red: 0.388, green: 0.400, blue: 0.965)       // indigo #6366F1
    static let accentPurple = Color(red: 0.545, green: 0.361, blue: 0.965) // #8B5CF6

    static func applyAppearance() {
        let bg = UIColor(background)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = bg
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = bg
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        UITableView.appearance().backgroundColor = bg
    }
}

/// Hides the default List/Form background so our own dark background shows through.
struct SeerrBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(SeerrTheme.background.ignoresSafeArea())
    }
}

extension View {
    func seerrBackground() -> some View {
        modifier(SeerrBackground())
    }
}
