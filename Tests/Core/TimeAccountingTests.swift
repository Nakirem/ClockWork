import XCTest
#if canImport(ClockWorkCore)
@testable import ClockWorkCore
#else
@testable import ClockWork
#endif

final class TimeAccountingTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func session(_ start: String = "2026-09-28T06:30:00Z", _ end: String = "2026-09-28T15:15:00Z") -> SessionRecord {
        SessionRecord(start: date(start), end: date(end), locationName: "Site", category: .work)
    }
    func testMultipleBreaks() throws {
        var value = session()
        value.breaks = [BreakRecord(start: date("2026-09-28T10:10:00Z"), end: date("2026-09-28T10:55:00Z"), kind: .lunch), BreakRecord(start: date("2026-09-28T13:32:00Z"), end: date("2026-09-28T13:42:00Z"))]
        try WorkRules.validate(value, among: [], now: date("2026-09-29T00:00:00Z"))
        let totals = TimeAccounting.totals(value, now: value.end!)
        XCTAssertEqual(totals.presence, 8.75 * 3600)
        XCTAssertEqual(totals.pauses, 55 * 60)
        XCTAssertEqual(totals.worked, 470 * 60)
    }
    func testEditingBreakRecalculatesImmediately() {
        var value = session()
        value.breaks = [BreakRecord(start: date("2026-09-28T10:05:00Z"), end: date("2026-09-28T11:05:00Z"))]
        let before = TimeAccounting.totals(value, now: value.end!).worked
        value.breaks[0].start = date("2026-09-28T10:10:00Z")
        value.breaks[0].end = date("2026-09-28T10:50:00Z")
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).worked, before + 20 * 60)
    }
    func testLiveBreakFreezesWorkedTime() {
        var value = session(); value.end = nil
        value.breaks = [BreakRecord(start: value.start.addingTimeInterval(3600))]
        XCTAssertEqual(TimeAccounting.totals(value, now: value.start.addingTimeInterval(7200)).worked, 3600)
        XCTAssertEqual(TimeAccounting.totals(value, now: value.start.addingTimeInterval(9000)).worked, 3600)
    }
    func testNoImplicitLunchDeduction() {
        let value = session()
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).worked, value.end!.timeIntervalSince(value.start))
    }
    func testActualLunchOf37Minutes() {
        var value = session(); value.breaks = [BreakRecord(start: value.start, end: value.start.addingTimeInterval(37 * 60), kind: .lunch)]
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).pauses, 37 * 60)
    }
    func testMidnightClippingAndBreak() {
        var value = session("2026-09-28T21:00:00Z", "2026-09-29T01:00:00Z") // 23:00–03:00 Paris
        value.breaks = [BreakRecord(start: date("2026-09-28T21:30:00Z"), end: date("2026-09-28T22:30:00Z"))]
        let first = TimeAccounting.totals(value, within: ParisTime.day(value.start), now: value.end!)
        let second = TimeAccounting.totals(value, within: ParisTime.day(value.end!), now: value.end!)
        XCTAssertEqual(first.worked, 1800); XCTAssertEqual(second.worked, 9000)
        XCTAssertEqual(first + second, TimeAccounting.totals(value, now: value.end!))
    }
    func testSpringDSTDayIs23Hours() {
        let day = ParisTime.day(date("2026-03-29T12:00:00Z"))
        XCTAssertEqual(day.duration, 23 * 3600)
        let value = session("2026-03-29T00:30:00Z", "2026-03-29T02:30:00Z")
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).worked, 7200)
        XCTAssertEqual(ParisTime.clock(value.start), "01:30"); XCTAssertEqual(ParisTime.clock(value.end!), "04:30")
    }
    func testAutumnDSTDayIs25HoursAndRepeatedHourIsDistinct() {
        XCTAssertEqual(ParisTime.day(date("2026-10-25T12:00:00Z")).duration, 25 * 3600)
        let value = session("2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z")
        XCTAssertEqual(ParisTime.clock(value.start), "02:30"); XCTAssertEqual(ParisTime.clock(value.end!), "02:30")
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).worked, 3600)
    }
    func testParisWeekStartsMondayRegardlessOfDeviceZone() {
        let week = ParisTime.week(date("2026-09-30T12:00:00Z"))
        XCTAssertEqual(week.start, date("2026-09-27T22:00:00Z"))
        XCTAssertEqual(ParisTime.day(date("2026-09-28T22:30:00Z")).start, date("2026-09-28T22:00:00Z"))
    }
    func testClippedWeekAcrossSundayMidnight() {
        let value = session("2026-09-27T21:00:00Z", "2026-09-27T23:00:00Z")
        XCTAssertEqual(TimeAccounting.totals(value, within: ParisTime.week(value.end!), now: value.end!).worked, 3600)
    }
    func testUnionDoesNotDoubleSubtractCorruptOverlappingBreaks() {
        var value = session()
        value.breaks = [BreakRecord(start: value.start, end: value.start.addingTimeInterval(3600)), BreakRecord(start: value.start.addingTimeInterval(1800), end: value.start.addingTimeInterval(5400))]
        XCTAssertEqual(TimeAccounting.totals(value, now: value.end!).pauses, 5400)
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.end!))
    }
    func testPendingExitFreezesCounters() {
        var value = session(); value.end = nil; value.pendingExit = value.start.addingTimeInterval(3600)
        XCTAssertEqual(TimeAccounting.totals(value, now: value.start.addingTimeInterval(5000)).worked, 3600)
    }
    func testSchoolSettingAndOtherCategory() {
        let work = session(); var school = session(); school.category = .school
        var other = session(); other.category = .other
        XCTAssertEqual(TimeAccounting.professional([work, school, other], includeSchool: true).count, 2)
        XCTAssertEqual(TimeAccounting.professional([work, school, other], includeSchool: false).count, 1)
    }
    func testOccupiedDaysAcrossMidnight() {
        let value = session("2026-09-28T21:00:00Z", "2026-09-29T01:00:00Z")
        XCTAssertEqual(TimeAccounting.occupiedDays([value], within: ParisTime.week(value.start), now: value.end!), 2)
    }
    func testRejectDepartureBeforeArrivalAndFuture() {
        var value = session(); value.end = value.start.addingTimeInterval(-1)
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: Date.distantFuture))
        value.end = value.start.addingTimeInterval(100)
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.start))
    }
    func testRejectTwoActiveSessionsEvenIfOneStartsLater() {
        var first = session(); first.end = nil
        var second = session(); second.start = first.start.addingTimeInterval(100); second.end = nil
        XCTAssertThrowsError(try WorkRules.validate(second, among: [first], now: Date.distantFuture))
    }
    func testRejectOverlapButAllowAdjacentSites() throws {
        let first = session()
        var second = session(); second.start = first.end!; second.end = second.start.addingTimeInterval(100)
        try WorkRules.validate(second, among: [first], now: second.end!)
        second.start = first.end!.addingTimeInterval(-1)
        XCTAssertThrowsError(try WorkRules.validate(second, among: [first], now: second.end!))
    }
    func testRejectBreakBeforeArrivalOrAfterDeparture() {
        var value = session()
        value.breaks = [BreakRecord(start: value.start.addingTimeInterval(-60), end: value.start)]
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.end!))
        value.breaks = [BreakRecord(start: value.end!, end: value.end!.addingTimeInterval(60))]
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.end!))
    }
    func testRejectTwoOpenBreaksAndOpenBreakInClosedSession() {
        var value = session(); value.breaks = [BreakRecord(start: value.start)]
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.end!))
        value.end = nil; value.breaks.append(BreakRecord(start: value.start))
        XCTAssertThrowsError(try WorkRules.validate(value, among: [], now: value.start.addingTimeInterval(100)))
    }
    func testClosingEndsActiveBreak() throws {
        var value = session(); let end = value.end!; value.end = nil
        value.breaks = [BreakRecord(start: value.start.addingTimeInterval(3600))]
        let closed = try WorkRules.closing(value, at: end, source: .manual)
        XCTAssertEqual(closed.breaks.first?.end, end)
        try WorkRules.validate(closed, among: [], now: end)
    }
    func testGeofenceDuplicatesAndGraceBoundary() {
        XCTAssertFalse(GeoRules.shouldHandle(previous: "inside", next: "inside"))
        XCTAssertFalse(GeoRules.shouldHandle(previous: "outside", next: "outside"))
        XCTAssertTrue(GeoRules.shouldHandle(previous: "outside", next: "inside"))
        let exit = date("2026-09-28T12:00:00Z")
        XCTAssertEqual(GeoRules.returning(exit: exit, at: exit.addingTimeInterval(599)), .cancelExit)
        XCTAssertEqual(GeoRules.returning(exit: exit, at: exit.addingTimeInterval(600)), .closeAndStart)
        XCTAssertFalse(GeoRules.exitIsDue(exit, now: exit.addingTimeInterval(599)))
        XCTAssertTrue(GeoRules.exitIsDue(exit, now: exit.addingTimeInterval(600)))
    }
    func testEditedAutomaticProvenance() {
        XCTAssertEqual(PunchSource.automaticLocation.edited, .editedAutomatic)
        XCTAssertEqual(PunchSource.editedAutomatic.edited, .editedAutomatic)
        XCTAssertEqual(PunchSource.manual.edited, .manual)
    }
}
