import AppKit
import UserNotifications

// MARK: - Notifications when a build or batch import finishes
//
// A first build takes 30–60 minutes, so a notification is posted when it ends –
// only while the app is in the background and only if enabled in Settings.

enum Notifier {
    /// UserDefaults key of the setting (Settings → General); read directly so Core stays independent.
    static let enabledKey = "notifyWhenBuildsFinish"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Asks once for permission (the system remembers the answer).
    static func requestAuthorizationIfNeeded() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isEnabled, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
