import SwiftUI

struct StatisticsView: View {
    @Environment(WorkStore.self) private var store
    @State private var period = 1
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let range = period == 0 ? ParisTime.day(timeline.date) : period == 1 ? ParisTime.week(timeline.date) : ParisTime.month(timeline.date)
                let totals = TimeAccounting.totals(store.sessions, within: range, now: timeline.date)
                let professional = TimeAccounting.totals(TimeAccounting.professional(store.sessions, includeSchool: store.settings.includeSchool), within: range, now: timeline.date)
                let days = TimeAccounting.occupiedDays(store.sessions, within: range, now: timeline.date)
                List {
                    Picker("Période", selection: $period) { Text("Jour").tag(0); Text("Semaine").tag(1); Text("Mois").tag(2) }.pickerStyle(.segmented)
                    Section("Durées") {
                        TotalsView(totals: totals)
                        LabeledContent("Moyenne / jour pointé", value: ParisTime.duration(days > 0 ? totals.worked / Double(days) : 0))
                        LabeledContent("Jours pointés", value: "\(days)")
                        LabeledContent("Total professionnel", value: ParisTime.duration(professional.worked))
                    }
                    if period == 1 || (period == 0 && store.settings.dailyGoalEnabled) {
                        Section("Objectif professionnel de la période entière") {
                            GoalView(worked: professional.worked, target: Double((period == 1 ? store.settings.weeklyMinutes : store.settings.dailyMinutes) * 60))
                        }
                    }
                    Section("Par catégorie") {
                        ForEach(LocationCategory.allCases) { category in
                            LabeledContent(category.title, value: ParisTime.duration(TimeAccounting.totals(store.sessions.filter { $0.category == category }, within: range, now: timeline.date).worked))
                        }
                    }
                    Section("Par lieu · heures travaillées") {
                        ForEach(locationGroups(range: range, now: timeline.date), id: \.id) { group in
                            LabeledContent(group.name, value: ParisTime.duration(group.worked))
                        }
                    }
                    Section {
                        Text("Les journées sont découpées à minuit à Paris. Le total professionnel inclut le travail\(store.settings.includeSchool ? " et l’école" : " uniquement"). La catégorie Autre reste visible séparément. La moyenne porte sur les jours ayant une présence.").font(.caption).foregroundStyle(.secondary)
                        if period == 2 { Text("L’objectif se suit par semaine ; aucun objectif mensuel n’est déduit arbitrairement.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Statistiques")
        }
    }
    private struct LocationTotal { var id: String; var name: String; var worked: TimeInterval }
    private func locationGroups(range: DateInterval, now: Date) -> [LocationTotal] {
        let groups = Dictionary(grouping: store.sessions) { $0.locationID?.uuidString ?? $0.locationName }
        return groups.compactMap { key, records -> LocationTotal? in
            let totals = TimeAccounting.totals(records, within: range, now: now)
            guard totals.presence > 0 else { return nil }
            return LocationTotal(id: key, name: records.first?.locationName ?? "Lieu", worked: totals.worked)
        }.sorted { $0.name < $1.name }
    }
}
