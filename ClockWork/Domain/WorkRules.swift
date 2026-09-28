import Foundation

enum LocationCategory: String, Codable, CaseIterable, Identifiable {
    case work, school, other
    var id: String { rawValue }
    var title: String { switch self { case .work: return "Travail"; case .school: return "École"; case .other: return "Autre" } }
    var symbol: String { switch self { case .work: return "briefcase.fill"; case .school: return "graduationcap.fill"; case .other: return "mappin.circle.fill" } }
}

enum PunchSource: String, Codable {
    case manual, automaticLocation, editedAutomatic
    var title: String { switch self { case .manual: return "Manuel"; case .automaticLocation: return "Automatique"; case .editedAutomatic: return "Automatique corrigé" } }
    var edited: Self { self == .manual ? .manual : .editedAutomatic }
}

enum BreakKind: String, Codable, CaseIterable, Identifiable {
    case lunch, rest, other
    var id: String { rawValue }
    var title: String { switch self { case .lunch: return "Déjeuner"; case .rest: return "Pause"; case .other: return "Autre" } }
}

struct BreakRecord: Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date?
    var kind: BreakKind = .rest
    var comment = ""
}

struct SessionRecord: Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date?
    var locationID: UUID?
    var locationName: String
    var category: LocationCategory
    var startSource: PunchSource = .manual
    var endSource: PunchSource = .manual
    var breaks: [BreakRecord] = []
    var lunchDismissed = false
    var pendingExit: Date?
    var needsReview = false
    var effectiveEnd: Date? { end ?? pendingExit }
    var openBreak: BreakRecord? { breaks.first { $0.end == nil } }
}

enum WorkError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

enum WorkRules {
    static func validate(_ session: SessionRecord, among others: [SessionRecord], now: Date) throws {
        guard session.start <= now else { throw WorkError.invalid("L’arrivée ne peut pas être dans le futur.") }
        if let end = session.end, end <= session.start || end > now {
            throw WorkError.invalid("Le départ doit suivre l’arrivée et ne peut pas être dans le futur.")
        }
        let upper = session.end ?? now
        let sorted = session.breaks.sorted { $0.start < $1.start }
        var previousEnd = session.start
        var openCount = 0
        for pause in sorted {
            let end = pause.end ?? upper
            if pause.end == nil { openCount += 1 }
            guard pause.start >= session.start, pause.start >= previousEnd,
                  pause.start <= upper, end >= pause.start, end <= upper,
                  pause.end != nil || session.end == nil else {
                throw WorkError.invalid("Les pauses doivent être dans la présence, sans chevauchement. Terminez la pause avant de clôturer la journée.")
            }
            previousEnd = end
        }
        guard openCount <= 1 else { throw WorkError.invalid("Une seule pause peut être active.") }
        if let exit = session.pendingExit, exit < session.start || exit > now || session.end != nil {
            throw WorkError.invalid("Le départ potentiel est incohérent.")
        }
        for other in others where other.id != session.id {
            if session.end == nil && other.end == nil { throw WorkError.invalid("Une journée est déjà en cours.") }
            if session.start < (other.end ?? .distantFuture) && other.start < (session.end ?? .distantFuture) {
                throw WorkError.invalid("Cette présence chevauche une autre présence.")
            }
        }
    }

    static func closing(_ session: SessionRecord, at date: Date, source: PunchSource) throws -> SessionRecord {
        guard date > session.start else { throw WorkError.invalid("Le départ doit suivre l’arrivée.") }
        var result = session
        result.end = date
        result.endSource = source
        result.pendingExit = nil
        result.breaks = try session.breaks.map { pause in
            var value = pause
            guard value.start <= date, (value.end ?? date) <= date else {
                throw WorkError.invalid("Une pause dépasse le départ choisi. Corrigez d’abord cette pause.")
            }
            if value.end == nil { value.end = date }
            return value
        }
        return result
    }
}

enum GeoRules {
    static let exitGrace: TimeInterval = 10 * 60
    static let shortVisit: TimeInterval = 3 * 60
    enum ReturnDecision: Equatable { case cancelExit, closeAndStart }
    static func returning(exit: Date, at date: Date) -> ReturnDecision {
        date.timeIntervalSince(exit) < exitGrace ? .cancelExit : .closeAndStart
    }
    static func shouldHandle(previous: String, next: String) -> Bool { previous != next }
    static func exitIsDue(_ exit: Date, now: Date) -> Bool { now.timeIntervalSince(exit) >= exitGrace }
}
