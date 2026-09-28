import SwiftUI
import SwiftData
import UIKit

@MainActor final class AppRuntime {
    static let shared = AppRuntime()
    var store: WorkStore?
    var location: LocationService?
    var notifications: NotificationService?
    var startupError: String?
    private init() {
        do {
            let schema = Schema([WorkLocation.self, WorkSession.self, BreakSession.self, AppSettings.self])
            var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ClockWork", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let configuration = ModelConfiguration("ClockWork", schema: schema, url: directory.appendingPathComponent("ClockWork.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let workStore = try WorkStore(container: container)
            let notificationService = NotificationService()
            store = workStore; notifications = notificationService
            workStore.onNotice = { [weak workStore, weak notificationService] notice in
                guard let workStore else { return }
                notificationService?.enqueue(notice, settings: workStore.settings)
            }
            workStore.cancelNotice = { [weak notificationService] id in notificationService?.cancel(id) }
            // Initialize on every launch, including a CoreLocation background relaunch.
            location = LocationService(store: workStore)
        } catch {
            // Never replace a failed on-disk store with an empty/in-memory database.
            startupError = error.localizedDescription
        }
    }
    func foreground() {
        location?.refresh()
        if let store { store.perform { try store.reconcile() } }
        Task { await notifications?.refresh() }
    }
}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = AppRuntime.shared
        return true
    }
}

@main struct ClockWorkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            if let store = AppRuntime.shared.store,
               let location = AppRuntime.shared.location,
               let notifications = AppRuntime.shared.notifications {
                RootView().environment(store).environment(location).environment(notifications)
                    .environment(\.timeZone, ParisTime.zone)
                    .environment(\.calendar, ParisTime.calendar)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            } else {
                ContentUnavailableView {
                    Label("Données indisponibles", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Le stockage n’a pas pu être ouvert. Vos données n’ont pas été effacées. Relancez l’app après avoir déverrouillé l’iPhone.\n\n\(AppRuntime.shared.startupError ?? "Erreur inconnue")")
                }
            }
        }
    }
}
