import Foundation
import SwiftData

@Model final class WorkLocation {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRaw: String
    var latitude: Double
    var longitude: Double
    var address: String
    var radius: Double
    var automatic: Bool
    var lastBoundary: String
    var lastBoundaryAt: Date?
    init(id: UUID = UUID(), name: String, category: LocationCategory, latitude: Double, longitude: Double, address: String = "", radius: Double = 150, automatic: Bool = false) {
        self.id = id; self.name = name; categoryRaw = category.rawValue
        self.latitude = latitude; self.longitude = longitude; self.address = address
        self.radius = radius; self.automatic = automatic; lastBoundary = "unknown"
    }
    var category: LocationCategory { LocationCategory(rawValue: categoryRaw) ?? .other }
}

@Model final class WorkSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    // Stable ID + snapshot: removing a location never removes or renames history.
    var locationID: UUID?
    var locationName: String
    var categoryRaw: String
    var startSourceRaw: String
    var endSourceRaw: String
    var pendingExit: Date?
    var lunchDismissed: Bool
    var needsReview: Bool
    @Relationship(deleteRule: .cascade, inverse: \BreakSession.session) var breaks: [BreakSession] = []
    init(_ record: SessionRecord) {
        id = record.id; startDate = record.start; endDate = record.end
        locationID = record.locationID; locationName = record.locationName; categoryRaw = record.category.rawValue
        startSourceRaw = record.startSource.rawValue; endSourceRaw = record.endSource.rawValue
        pendingExit = record.pendingExit; lunchDismissed = record.lunchDismissed; needsReview = record.needsReview
    }
    var record: SessionRecord {
        SessionRecord(id: id, start: startDate, end: endDate, locationID: locationID, locationName: locationName,
                      category: LocationCategory(rawValue: categoryRaw) ?? .other,
                      startSource: PunchSource(rawValue: startSourceRaw) ?? .manual,
                      endSource: PunchSource(rawValue: endSourceRaw) ?? .manual,
                      breaks: breaks.map(\.record), lunchDismissed: lunchDismissed, pendingExit: pendingExit, needsReview: needsReview)
    }
}

@Model final class BreakSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var kindRaw: String
    var comment: String
    var session: WorkSession?
    init(_ record: BreakRecord) {
        id = record.id; startDate = record.start; endDate = record.end; kindRaw = record.kind.rawValue; comment = record.comment
    }
    var record: BreakRecord { BreakRecord(id: id, start: startDate, end: endDate, kind: BreakKind(rawValue: kindRaw) ?? .rest, comment: comment) }
}

@Model final class AppSettings {
    @Attribute(.unique) var key: String
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
    init() {
        key = "main"; weeklyMinutes = 2100; dailyMinutes = 420; dailyGoalEnabled = true
        includeSchool = true; lunchMinutes = 60; lunchStartMinute = 720
        notifyArrival = true; notifyDeparture = true; notifyBreakStart = false
        notifyBreakEnd = false; notifyMissingLunch = true
    }
}
