import Foundation

enum ParisTime {
    static let zone = TimeZone(identifier: "Europe/Paris")!
    static var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = zone
        value.locale = Locale(identifier: "fr_FR")
        value.firstWeekday = 2
        return value
    }
    static func day(_ date: Date) -> DateInterval { calendar.dateInterval(of: .day, for: date)! }
    static func week(_ date: Date) -> DateInterval { calendar.dateInterval(of: .weekOfYear, for: date)! }
    static func month(_ date: Date) -> DateInterval { calendar.dateInterval(of: .month, for: date)! }
    static func shifted(_ date: Date, days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    static func clock(_ date: Date) -> String { format(date, pattern: "HH:mm") }
    static func label(_ date: Date) -> String { format(date, pattern: "EEEE d MMMM yyyy") }
    static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return String(format: "%02d h %02d", minutes / 60, minutes % 60)
    }
    static func lunch(on date: Date, minute: Int, duration: Int) -> DateInterval {
        let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date)!
        return DateInterval(start: start, duration: TimeInterval(duration * 60))
    }
}

struct TimeTotals: Equatable {
    var presence: TimeInterval = 0
    var pauses: TimeInterval = 0
    var worked: TimeInterval { max(0, presence - pauses) }
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(presence: lhs.presence + rhs.presence, pauses: lhs.pauses + rhs.pauses)
    }
}

enum TimeAccounting {
    static func totals(_ session: SessionRecord, within range: DateInterval? = nil, now: Date) -> TimeTotals {
        let start = max(session.start, range?.start ?? session.start)
        let end = min(session.effectiveEnd ?? now, now, range?.end ?? .distantFuture)
        guard end > start else { return TimeTotals() }
        // Union protects totals even if an imported/corrupt record has overlapping pauses.
        let spans = session.breaks.compactMap { pause -> DateInterval? in
            let a = max(start, pause.start)
            let b = min(end, pause.end ?? now)
            return b > a ? DateInterval(start: a, end: b) : nil
        }.sorted { $0.start < $1.start }
        var pauseTotal: TimeInterval = 0
        var cursor = start
        for span in spans {
            let a = max(cursor, span.start)
            if span.end > a { pauseTotal += span.end.timeIntervalSince(a) }
            cursor = max(cursor, span.end)
        }
        return TimeTotals(presence: end.timeIntervalSince(start), pauses: pauseTotal)
    }
    static func totals(_ sessions: [SessionRecord], within range: DateInterval, now: Date) -> TimeTotals {
        sessions.reduce(TimeTotals()) { $0 + totals($1, within: range, now: now) }
    }
    static func professional(_ sessions: [SessionRecord], includeSchool: Bool) -> [SessionRecord] {
        sessions.filter { $0.category == .work || (includeSchool && $0.category == .school) }
    }
    static func occupiedDays(_ sessions: [SessionRecord], within range: DateInterval, now: Date) -> Int {
        var day = ParisTime.day(range.start).start
        var count = 0
        while day < min(range.end, now) {
            let next = ParisTime.shifted(day, days: 1)
            if totals(sessions, within: DateInterval(start: max(day, range.start), end: min(next, range.end)), now: now).presence > 0 { count += 1 }
            day = next
        }
        return count
    }
}
