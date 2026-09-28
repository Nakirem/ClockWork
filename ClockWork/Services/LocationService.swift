import Foundation
import Observation
import UIKit
@preconcurrency import CoreLocation

@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: WorkStore
    var authorization: CLAuthorizationStatus = .notDetermined
    var precise = true
    var servicesEnabled = true
    var backgroundAvailable = true
    var monitoringAvailable = true
    var currentCoordinate: CLLocationCoordinate2D?
    var lastError: String?
    var locating = false
    var monitoredCount = 0
    private var requestAfterPermission = false
    private var oneShotTimeout: Task<Void, Never>?
    private let prefix = "clockwork."

    var status: String {
        if !servicesEnabled { return "Localisation désactivée" }
        if !monitoringAvailable { return "Zones indisponibles sur cet appareil" }
        switch authorization {
        case .denied, .restricted: return "Permission requise dans les réglages iOS"
        case .notDetermined: return "Permission requise"
        case .authorizedWhenInUse: return "Permission « Toujours » requise"
        case .authorizedAlways:
            if !precise { return "Position précise requise" }
            if !backgroundAvailable { return "Actualisation en arrière-plan désactivée" }
            if lastError != nil { return "Surveillance à vérifier" }
            return monitoredCount == 0 ? "Aucun lieu automatique surveillé" : "Active — \(monitoredCount) zone(s)"
        @unknown default: return "Permission à vérifier"
        }
    }
    init(store: WorkStore) {
        self.store = store
        super.init()
        // CLLocationManager is created on the main actor: its delegate uses the main run loop.
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refresh()
    }
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }
    func refresh() {
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        servicesEnabled = CLLocationManager.locationServicesEnabled()
        backgroundAvailable = UIApplication.shared.backgroundRefreshStatus == .available
        monitoringAvailable = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        syncRegions()
    }
    func syncRegions() {
        let canMonitor = servicesEnabled && monitoringAvailable && authorization == .authorizedAlways && precise
        let desired = canMonitor ? Array(store.locations.filter(\.automatic).prefix(20)) : []
        let identifiers = Set(desired.map { prefix + $0.id.uuidString })
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) {
            guard let circle = region as? CLCircularRegion,
                  let location = desired.first(where: { prefix + $0.id.uuidString == region.identifier }),
                  identifiers.contains(region.identifier), circle.center.latitude == location.latitude,
                  circle.center.longitude == location.longitude,
                  abs(circle.radius - effectiveRadius(location.radius)) < 1 else {
                manager.stopMonitoring(for: region); continue
            }
        }
        for location in desired {
            let id = prefix + location.id.uuidString
            if let existing = manager.monitoredRegions.first(where: { $0.identifier == id }) as? CLCircularRegion,
               existing.center.latitude == location.latitude, existing.center.longitude == location.longitude,
               abs(existing.radius - effectiveRadius(location.radius)) < 1 {
                manager.requestState(for: existing)
            } else {
                let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), radius: effectiveRadius(location.radius), identifier: id)
                region.notifyOnEntry = true; region.notifyOnExit = true
                manager.startMonitoring(for: region)
            }
        }
        monitoredCount = manager.monitoredRegions.filter { identifiers.contains($0.identifier) }.count
    }
    private func effectiveRadius(_ requested: Double) -> Double {
        let maximum = manager.maximumRegionMonitoringDistance
        return maximum > 0 ? min(requested, maximum) : requested
    }
    func locateOnce() {
        currentCoordinate = nil; lastError = nil
        if authorization == .notDetermined { requestAfterPermission = true; requestWhenInUse(); return }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            lastError = "Autorisez la localisation dans les réglages iOS."; return
        }
        locating = true; manager.requestLocation()
        oneShotTimeout?.cancel()
        oneShotTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.locating else { return }
            self.locating = false; self.lastError = "Position indisponible. Réessayez ou choisissez sur la carte."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
        if requestAfterPermission, authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            requestAfterPermission = false; locateOnce()
        }
    }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        lastError = nil
        monitoredCount = manager.monitoredRegions.filter { $0.identifier.hasPrefix(prefix) }.count
        manager.requestState(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { receive(region, inside: true) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { receive(region, inside: false) }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside { receive(region, inside: true) }
        else if state == .outside { receive(region, inside: false) }
    }
    private func receive(_ region: CLRegion, inside: Bool) {
        guard authorization == .authorizedAlways, precise, region.identifier.hasPrefix(prefix),
              let id = UUID(uuidString: String(region.identifier.dropFirst(prefix.count))),
              let location = store.locations.first(where: { $0.id == id && $0.automatic }),
              let circle = region as? CLCircularRegion,
              circle.center.latitude == location.latitude, circle.center.longitude == location.longitude,
              abs(circle.radius - effectiveRadius(location.radius)) < 1 else { return }
        // Ignore callbacks still queued for an older geometry of an edited zone.
        store.perform { try store.boundary(locationID: id, inside: inside) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locating, let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) < 60 else { return }
        oneShotTimeout?.cancel(); locating = false; currentCoordinate = value.coordinate
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        oneShotTimeout?.cancel(); locating = false; lastError = error.localizedDescription
    }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        lastError = "La surveillance d’une zone a échoué : \(error.localizedDescription)"
    }
}
