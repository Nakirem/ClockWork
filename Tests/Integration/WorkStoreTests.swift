import XCTest
import SwiftData
@testable import ClockWork

@MainActor final class WorkStoreTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-09-28T06:00:00Z")!
    private func fixture() throws -> (WorkStore, ModelContainer, UUID) {
        let schema = Schema([WorkLocation.self, WorkSession.self, BreakSession.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let store = try WorkStore(container: container)
        var location = LocationDraft(); location.name = "Site 1"; location.automatic = true
        try store.saveLocation(location)
        return (store, container, location.id)
    }
    func testDuplicateEntriesAndExitsAreIdempotent() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        try store.boundary(locationID: id, inside: true, now: start.addingTimeInterval(20))
        XCTAssertEqual(store.sessions.count, 1)
        let exit = start.addingTimeInterval(3600)
        try store.boundary(locationID: id, inside: false, now: exit)
        try store.boundary(locationID: id, inside: false, now: exit.addingTimeInterval(30))
        XCTAssertEqual(store.active?.pendingExit, exit)
        try store.reconcile(now: exit.addingTimeInterval(601))
        try store.boundary(locationID: id, inside: false, now: exit.addingTimeInterval(700))
        XCTAssertEqual(store.sessions.count, 1); XCTAssertEqual(store.sessions[0].end, exit)
    }
    func testQuickReturnCancelsExit() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        try store.boundary(locationID: id, inside: false, now: start.addingTimeInterval(3600))
        try store.boundary(locationID: id, inside: true, now: start.addingTimeInterval(3900))
        XCTAssertNotNil(store.active); XCTAssertNil(store.active?.pendingExit); XCTAssertEqual(store.sessions.count, 1)
    }
    func testLongReturnCreatesTwoSessionsWithAnUnworkedGap() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        try store.boundary(locationID: id, inside: false, now: start.addingTimeInterval(3600))
        try store.boundary(locationID: id, inside: true, now: start.addingTimeInterval(7200))
        XCTAssertEqual(store.sessions.count, 2)
        let totals = TimeAccounting.totals(store.sessions, within: ParisTime.day(start), now: start.addingTimeInterval(10800))
        XCTAssertEqual(totals.worked, 7200)
    }
    func testPendingExitAndBoundarySurviveNewContext() throws {
        let (store, container, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        let exit = start.addingTimeInterval(3600)
        try store.boundary(locationID: id, inside: false, now: exit)
        let reopened = try WorkStore(container: container)
        XCTAssertEqual(reopened.active?.pendingExit, exit)
        XCTAssertEqual(reopened.locations.first?.lastBoundary, "outside")
        try reopened.reconcile(now: exit.addingTimeInterval(601))
        XCTAssertEqual(reopened.sessions.first?.end, exit)
    }
    func testManualPausePreventsAutomaticDeparture() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        try store.beginBreak(.lunch, now: start.addingTimeInterval(3600))
        try store.boundary(locationID: id, inside: false, now: start.addingTimeInterval(3601))
        try store.reconcile(now: start.addingTimeInterval(8000))
        XCTAssertNotNil(store.active); XCTAssertNil(store.active?.pendingExit)
        try store.boundary(locationID: id, inside: true, now: start.addingTimeInterval(8100))
        try store.endBreak(now: start.addingTimeInterval(8200))
        XCTAssertNil(store.active?.openBreak)
        XCTAssertEqual(store.active?.breaks.count, 1)
    }
    func testDeleteLocationPreservesHistory() throws {
        let (store, _, id) = try fixture()
        try store.start(locationID: id, now: start)
        try store.deleteLocation(id)
        XCTAssertEqual(store.sessions.first?.locationName, "Site 1")
        XCTAssertEqual(store.sessions.first?.locationID, id)
        XCTAssertTrue(store.locations.isEmpty)
    }
    func testRejectedEditDoesNotMutateSavedData() throws {
        let (store, container, id) = try fixture()
        try store.start(locationID: id, now: start)
        var draft = try XCTUnwrap(store.active); draft.end = start.addingTimeInterval(-1)
        XCTAssertThrowsError(try store.saveSession(draft, now: start))
        let reopened = try WorkStore(container: container)
        XCTAssertNil(reopened.active?.end); XCTAssertEqual(reopened.active?.start, start)
    }
    func testNoSecondActiveSession() throws {
        let (store, _, id) = try fixture()
        try store.start(locationID: id, now: start)
        XCTAssertThrowsError(try store.start(locationID: id, now: start.addingTimeInterval(1)))
        XCTAssertEqual(store.sessions.count, 1)
    }
    func testShortVisitIsFlaggedAndKept() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        try store.boundary(locationID: id, inside: false, now: start.addingTimeInterval(60))
        try store.reconcile(now: start.addingTimeInterval(900))
        XCTAssertTrue(store.sessions[0].needsReview); XCTAssertEqual(store.sessions.count, 1)
    }
    func testEditedAutomaticArrivalIsMarked() throws {
        let (store, _, id) = try fixture()
        try store.boundary(locationID: id, inside: true, now: start)
        var record = try XCTUnwrap(store.active); record.start = start.addingTimeInterval(-60)
        try store.saveSession(record, now: start)
        XCTAssertEqual(store.active?.startSource, .editedAutomatic)
    }
    func testBreakUpdatesDoNotDuplicateRelationshipsAndDeletionCascades() throws {
        let (store, container, id) = try fixture()
        try store.start(locationID: id, now: start)
        try store.beginBreak(.lunch, now: start.addingTimeInterval(100))
        try store.endBreak(now: start.addingTimeInterval(200))
        XCTAssertEqual(store.active?.breaks.count, 1)
        let sessionID = try XCTUnwrap(store.active?.id)
        try store.deleteSession(sessionID)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BreakSession>()), 0)
    }
    func testLimitOf20AutomaticLocations() throws {
        let (store, _, _) = try fixture()
        for index in 2...20 { var draft = LocationDraft(); draft.name = "Site \(index)"; draft.automatic = true; try store.saveLocation(draft) }
        var excess = LocationDraft(); excess.name = "Site 21"; excess.automatic = true
        XCTAssertThrowsError(try store.saveLocation(excess))
        excess.automatic = false; try store.saveLocation(excess)
        XCTAssertEqual(store.locations.count, 21)
    }
    func testTransitionToSecondSiteClosesPendingFirstSite() throws {
        let (store, _, first) = try fixture()
        var second = LocationDraft(); second.name = "École"; second.category = .school; second.automatic = true
        try store.saveLocation(second)
        try store.boundary(locationID: first, inside: true, now: start)
        try store.boundary(locationID: first, inside: false, now: start.addingTimeInterval(3600))
        try store.boundary(locationID: second.id, inside: true, now: start.addingTimeInterval(3650))
        XCTAssertEqual(store.sessions.count, 2); XCTAssertEqual(store.active?.locationID, second.id)
        XCTAssertEqual(store.sessions.first(where: { $0.locationID == first })?.end, start.addingTimeInterval(3600))
    }
}
