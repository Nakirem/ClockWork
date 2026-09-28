import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor @Observable final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var status = "Non demandé"
    var lastError: String?
    override init() { super.init(); center.delegate = self }
    func refresh() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: status = "Autorisées"
        case .denied: status = "Refusées — ouvrir les réglages iOS"
        case .notDetermined: status = "Non demandé"
        @unknown default: status = "À vérifier"
        }
    }
    func request() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]); await refresh() }
        catch { lastError = error.localizedDescription }
    }
    func enqueue(_ notice: WorkNotice, settings: AppSettings) {
        let enabled: Bool
        switch notice.kind {
        case .arrival: enabled = settings.notifyArrival
        case .departure: enabled = settings.notifyDeparture
        case .breakStart: enabled = settings.notifyBreakStart
        case .breakEnd: enabled = settings.notifyBreakEnd
        case .missingLunch: enabled = settings.notifyMissingLunch
        }
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title; content.body = notice.body; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notice.delay), repeats: false)
        // Queue immediately while handling the location callback's short background window.
        center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)) { [weak self] error in
            if let error { Task { @MainActor in self?.lastError = error.localizedDescription } }
        }
    }
    func cancel(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
