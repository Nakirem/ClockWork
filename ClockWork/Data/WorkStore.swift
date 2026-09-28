import Foundation
import Observation
import SwiftData

struct LocationDraft {
    var id = UUID()
    var name = ""
    var category: LocationCategory = .work
    var latitude = 48.8566
    var longitude = 2.3522
    var address = ""
    var radius = 150.0
    var automatic = false
    init() {}
    init(_ location: WorkLocation) {
        id = location.id; name = location.name; category = location.category
        latitude = location.latitude; longitude = location.longitude; address = location.address
        radius = location.radius; automatic = location.automatic
    }
}

struct SettingsDraft {
    var weeklyMinutes: Int
    var dailyMinutes: Int
    var dailyGoalEnabled: Bool
    var includeSchool: Bool
    var lunchMinutes: Int
    var lunchStartMinute: Int
    var notifyArrival: Bool
    var notifyDeparture: Bool
    var notifyBreakStart: Bool
    var notifyBreakEnd: Bool
    var notifyMissingLunch: Bool
    init(_ value: AppSettings) {
        weeklyMinutes = value.weeklyMinutes; dailyMinutes = value.dailyMinutes
        dailyGoalEnabled = value.dailyGoalEnabled; includeSchool = value.includeSchool
        lunchMinutes = value.lunchMinutes; lunchStartMinute = value.lunchStartMinute
        notifyArrival = value.notifyArrival; notifyDeparture = value.notifyDeparture
        notifyBreakStart = value.notifyBreakStart; notifyBreakEnd = value.notifyBreakEnd
        notifyMissingLunch = value.notifyMissingLunch
    }
}

enum NoticeKind { case arrival, departure, breakStart, breakEnd, missingLunch }
struct WorkNotice {
    var id: String
    var kind: NoticeKind
    var title: String
    var body: String
    var delay: TimeInterval = 1
}

@MainActor @Observable final class WorkStore {
    private let context: ModelContext
    private(set) var locations: [WorkLocation] = []
    private(set) var sessions: [SessionRecord] = []
    private(set) var settings: AppSettings
    var errorMessage: String?
    var geoMessage: String?
    @ObservationIgnored var onNotice: ((WorkNotice) -> Void)?
    @ObservationIgnored var cancelNotice: ((String) -> Void)?
    var active: SessionRecord? { sessions.first { $0.end == nil } }

    init(container: ModelContainer) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first { settings = existing }
        else { settings = AppSettings(); context.insert(settings); try context.save() }
        try reload()
    }

    private func reload() throws {
        locations = try context.fetch(FetchDescriptor<WorkLocation>(sortBy: [SortDescriptor(\WorkLocation.name)]))
        sessions = try context.fetch(FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\WorkSession.startDate, order: .reverse)])).map(\.record)
    }
    private func commit(_ body: () throws -> Void) throws {
        do { try body(); try context.save(); try reload() }
        catch { context.rollback(); try? reload(); throw error }
    }
    @discardableResult func perform(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    private func model(_ id: UUID) throws -> WorkSession {
        let descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == id })
        guard let result = try context.fetch(descriptor).first else { throw WorkError.invalid("Cette présence n’existe plus.") }
        return result
    }
    private func write(_ record: SessionRecord) throws {
        let id = record.id
        let existing = try context.fetch(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == id })).first
        let value = existing ?? WorkSession(record)
        if existing == nil { context.insert(value) }
        value.startDate = record.start; value.endDate = record.end
        value.locationID = record.locationID; value.locationName = record.locationName; value.categoryRaw = record.category.rawValue
        value.startSourceRaw = record.startSource.rawValue; value.endSourceRaw = record.endSource.rawValue
        value.pendingExit = record.pendingExit; value.lunchDismissed = record.lunchDismissed; value.needsReview = record.needsReview
        let oldBreaks = value.breaks
        for old in oldBreaks where !record.breaks.contains(where: { $0.id == old.id }) {
            value.breaks.removeAll { $0.id == old.id }; context.delete(old)
        }
        for pause in record.breaks {
            if let old = value.breaks.first(where: { $0.id == pause.id }) {
                old.startDate = pause.start; old.endDate = pause.end; old.kindRaw = pause.kind.rawValue; old.comment = pause.comment
            } else {
                let added = BreakSession(pause); context.insert(added); value.breaks.append(added)
            }
        }
    }
    func saveSession(_ draft: SessionRecord, edited: Bool = true, now: Date = Date()) throws {
        var record = draft
        if edited, let previous = sessions.first(where: { $0.id == record.id }) {
            if previous.start != record.start || previous.locationID != record.locationID { record.startSource = previous.startSource.edited }
            if previous.end != record.end { record.endSource = previous.endSource.edited }
            if previous.pendingExit != nil && record.end != nil { record.endSource = .editedAutomatic }
            record.pendingExit = nil
            record.needsReview = false
        }
        try WorkRules.validate(record, among: sessions, now: now)
        try commit { try write(record) }
        cancelNotice?("exit-\(record.id)")
        scheduleLunch(record, now: now)
    }
    func deleteSession(_ id: UUID) throws {
        try commit { context.delete(try model(id)) }
        cancelNotice?("exit-\(id)"); cancelNotice?("lunch-\(id)")
    }
    func start(locationID: UUID, now: Date = Date()) throws {
        guard let location = locations.first(where: { $0.id == locationID }) else { throw WorkError.invalid("Choisissez un lieu.") }
        let record = SessionRecord(start: now, locationID: location.id, locationName: location.name, category: location.category)
        try WorkRules.validate(record, among: sessions, now: now)
        try commit { try write(record) }
        scheduleLunch(record, now: now)
    }
    func finish(_ id: UUID, at date: Date = Date()) throws {
        guard let session = sessions.first(where: { $0.id == id && $0.end == nil }) else { return }
        let record = try WorkRules.closing(session, at: date, source: .manual)
        try saveSession(record, edited: false)
    }
    func beginBreak(_ kind: BreakKind, now: Date = Date()) throws {
        guard var record = active, record.openBreak == nil else { throw WorkError.invalid("Une pause est déjà active ou aucune journée n’est commencée.") }
        record.pendingExit = nil
        record.breaks.append(BreakRecord(start: now, kind: kind))
        try saveSession(record, edited: false, now: now)
        onNotice?(WorkNotice(id: UUID().uuidString, kind: .breakStart, title: "Pause commencée", body: "\(kind.title) — \(ParisTime.clock(now))"))
    }
    func endBreak(now: Date = Date()) throws {
        guard var record = active, let index = record.breaks.firstIndex(where: { $0.end == nil }) else { return }
        record.breaks[index].end = now
        if let location = locations.first(where: { $0.id == record.locationID }), location.automatic, location.lastBoundary == "outside" {
            record.pendingExit = now
        }
        try saveSession(record, edited: false, now: now)
        onNotice?(WorkNotice(id: UUID().uuidString, kind: .breakEnd, title: "Pause terminée", body: ParisTime.clock(now)))
        if let exit = record.pendingExit { scheduleExit(record, exit: exit) }
    }
    func addUsualLunch(to id: UUID, now: Date = Date()) throws {
        guard var record = sessions.first(where: { $0.id == id }) else { return }
        guard !record.breaks.contains(where: { $0.kind == .lunch }) else { throw WorkError.invalid("Un déjeuner est déjà enregistré. Modifiez-le dans le détail.") }
        let interval = ParisTime.lunch(on: record.start, minute: settings.lunchStartMinute, duration: settings.lunchMinutes)
        record.breaks.append(BreakRecord(start: interval.start, end: interval.end, kind: .lunch))
        try saveSession(record, now: now)
    }
    func dismissLunch(_ id: UUID) throws {
        guard var record = sessions.first(where: { $0.id == id }) else { return }
        record.lunchDismissed = true; try saveSession(record, edited: false)
    }
    func cancelExit(_ id: UUID) throws {
        guard var record = active, record.id == id else { return }
        record.pendingExit = nil; try saveSession(record, edited: false)
    }
    func confirmExit(_ id: UUID) throws {
        guard let record = active, record.id == id, let exit = record.pendingExit else { return }
        let result = try automaticClose(record, exit: exit)
        try saveSession(result, edited: false)
        departureNotice(result)
    }
    private func automaticClose(_ record: SessionRecord, exit: Date) throws -> SessionRecord {
        var result = try WorkRules.closing(record, at: max(exit, record.start.addingTimeInterval(1)), source: .automaticLocation)
        result.needsReview = exit.timeIntervalSince(record.start) < GeoRules.shortVisit
        return result
    }
    func reconcile(now: Date = Date()) throws {
        guard let record = active, let exit = record.pendingExit, GeoRules.exitIsDue(exit, now: now) else { return }
        let result = try automaticClose(record, exit: exit)
        try WorkRules.validate(result, among: sessions, now: now)
        try commit { try write(result) }
        cancelNotice?("exit-\(record.id)"); departureNotice(result); scheduleLunch(result, now: now)
    }

    // A boundary and all resulting session mutations are committed in one transaction.
    func boundary(locationID: UUID, inside: Bool, now: Date = Date()) throws {
        guard let location = locations.first(where: { $0.id == locationID && $0.automatic }) else { return }
        let next = inside ? "inside" : "outside"
        guard GeoRules.shouldHandle(previous: location.lastBoundary, next: next) else {
            if !inside { try reconcile(now: now) }
            return
        }
        var current = active
        var changed: [SessionRecord] = []
        var notices: [WorkNotice] = []
        var cancelIDs: [String] = []
        if let record = current, let exit = record.pendingExit {
            if inside && record.locationID == locationID && GeoRules.returning(exit: exit, at: now) == .cancelExit {
                var returned = record; returned.pendingExit = nil; changed.append(returned); current = returned
                cancelIDs.append("exit-\(record.id)")
            } else if GeoRules.exitIsDue(exit, now: now) || (inside && record.locationID != locationID) {
                let closed = try automaticClose(record, exit: exit)
                changed.append(closed); current = nil; cancelIDs.append("exit-\(record.id)")
                notices.append(departure(closed))
            }
        }
        if inside && current == nil {
            let record = SessionRecord(start: now, locationID: location.id, locationName: location.name, category: location.category, startSource: .automaticLocation)
            changed.append(record)
            notices.append(WorkNotice(id: "arrival-\(record.id)", kind: .arrival, title: "Arrivée détectée", body: "\(location.name) à \(ParisTime.clock(now))"))
        } else if !inside, var record = current, record.locationID == locationID, record.pendingExit == nil {
            // A manually started pause takes priority, even outside the region.
            if record.openBreak == nil {
                record.pendingExit = now; changed.append(record)
                notices.append(exitNotice(record, exit: now))
            }
        } else if inside, let record = current, record.locationID != locationID {
            geoMessage = "\(location.name) détecté, mais une présence à \(record.locationName) est active. Vérifiez le lieu et le départ."
        }
        var candidates = sessions
        for record in changed { candidates.removeAll { $0.id == record.id }; candidates.append(record) }
        for record in changed { try WorkRules.validate(record, among: candidates, now: now) }
        try commit {
            location.lastBoundary = next; location.lastBoundaryAt = now
            for record in changed { try write(record) }
        }
        cancelIDs.forEach { cancelNotice?($0) }
        notices.forEach { onNotice?($0) }
        for record in changed { scheduleLunch(record, now: now) }
    }

    func saveLocation(_ draft: LocationDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.latitude.isFinite, draft.longitude.isFinite, draft.radius.isFinite,
              (-90...90).contains(draft.latitude), (-180...180).contains(draft.longitude), (50...1000).contains(draft.radius) else {
            throw WorkError.invalid("Renseignez un nom, des coordonnées valides et un rayon entre 50 et 1 000 mètres.")
        }
        guard !draft.automatic || locations.filter({ $0.automatic && $0.id != draft.id }).count < 20 else {
            throw WorkError.invalid("iOS autorise 20 zones simultanées. Désactivez un autre lieu.")
        }
        let old = locations.first { $0.id == draft.id }
        let geometryChanged = old.map { $0.latitude != draft.latitude || $0.longitude != draft.longitude || $0.radius != draft.radius || $0.automatic != draft.automatic } ?? false
        try commit {
            let value = old ?? WorkLocation(id: draft.id, name: draft.name, category: draft.category, latitude: draft.latitude, longitude: draft.longitude)
            if old == nil { context.insert(value) }
            value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); value.categoryRaw = draft.category.rawValue
            value.latitude = draft.latitude; value.longitude = draft.longitude; value.radius = draft.radius
            value.address = draft.address; value.automatic = draft.automatic
            if geometryChanged { value.lastBoundary = "unknown"; value.lastBoundaryAt = nil }
            if geometryChanged, var record = active, record.locationID == value.id { record.pendingExit = nil; try write(record) }
        }
        if geometryChanged, let record = active, record.locationID == draft.id { cancelNotice?("exit-\(record.id)") }
    }
    func deleteLocation(_ id: UUID) throws {
        guard let value = locations.first(where: { $0.id == id }) else { return }
        let activeID = active?.locationID == id ? active?.id : nil
        try commit {
            if var record = active, record.locationID == id { record.pendingExit = nil; try write(record) }
            context.delete(value)
        }
        if let activeID { cancelNotice?("exit-\(activeID)") }
    }
    func saveSettings(_ draft: SettingsDraft) throws {
        guard (1...10080).contains(draft.weeklyMinutes), (1...1440).contains(draft.dailyMinutes),
              (1...480).contains(draft.lunchMinutes), (0...1439).contains(draft.lunchStartMinute) else {
            throw WorkError.invalid("Vérifiez les objectifs et la durée du déjeuner.")
        }
        try commit {
            settings.weeklyMinutes = draft.weeklyMinutes; settings.dailyMinutes = draft.dailyMinutes
            settings.dailyGoalEnabled = draft.dailyGoalEnabled; settings.includeSchool = draft.includeSchool
            settings.lunchMinutes = draft.lunchMinutes; settings.lunchStartMinute = draft.lunchStartMinute
            settings.notifyArrival = draft.notifyArrival; settings.notifyDeparture = draft.notifyDeparture
            settings.notifyBreakStart = draft.notifyBreakStart; settings.notifyBreakEnd = draft.notifyBreakEnd
            settings.notifyMissingLunch = draft.notifyMissingLunch
        }
        for record in sessions { cancelNotice?("lunch-\(record.id)"); cancelNotice?("exit-\(record.id)") }
        if let record = active {
            scheduleLunch(record, now: Date())
            if let exit = record.pendingExit { scheduleExit(record, exit: exit) }
        }
    }
    private func exitNotice(_ record: SessionRecord, exit: Date) -> WorkNotice {
        WorkNotice(id: "exit-\(record.id)", kind: .departure, title: "Départ potentiel à vérifier", body: "Sortie de \(record.locationName) à \(ParisTime.clock(exit)). Un retour rapide annule ce départ ; ouvrez ClockWork pour vérifier.", delay: max(1, exit.addingTimeInterval(GeoRules.exitGrace).timeIntervalSinceNow))
    }
    private func scheduleExit(_ record: SessionRecord, exit: Date) { onNotice?(exitNotice(record, exit: exit)) }
    private func departure(_ record: SessionRecord) -> WorkNotice {
        WorkNotice(id: "departure-\(record.id)", kind: .departure, title: "Départ enregistré", body: "\(record.locationName) à \(ParisTime.clock(record.end ?? Date()))")
    }
    private func departureNotice(_ record: SessionRecord) { onNotice?(departure(record)) }
    private func scheduleLunch(_ record: SessionRecord, now: Date) {
        cancelNotice?("lunch-\(record.id)")
        guard !record.lunchDismissed, !record.breaks.contains(where: { $0.kind == .lunch }) else { return }
        let usual = ParisTime.lunch(on: record.start, minute: settings.lunchStartMinute, duration: settings.lunchMinutes)
        guard record.start <= usual.start, (record.end ?? .distantFuture) >= usual.end else { return }
        onNotice?(WorkNotice(id: "lunch-\(record.id)", kind: .missingLunch, title: "Pause déjeuner", body: "Aucune pause déjeuner enregistrée pour la présence du \(ParisTime.format(record.start, pattern: "d MMMM")). Ajoutez-la ou choisissez « Aucune pause ».", delay: max(1, usual.end.addingTimeInterval(3 * 3600).timeIntervalSince(now))))
    }
}
