import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var deviceToken: String?
    @Published private(set) var isAuthorized = false
    @Published var registrationError: String?

    private init() {}

    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            registrationError = nil
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            registrationError = error.localizedDescription
        }
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        registrationError = nil
    }

    func didFailToRegister(error: Error) {
        deviceToken = nil
        registrationError = error.localizedDescription
    }
}
