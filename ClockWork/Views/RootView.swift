import SwiftUI

struct RootView: View {
    @Environment(WorkStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var store = store
        TabView {
            TodayView().tabItem { Label("Aujourd’hui", systemImage: "clock") }
            HistoryView().tabItem { Label("Historique", systemImage: "calendar") }
            LocationsView().tabItem { Label("Lieux", systemImage: "mappin.and.ellipse") }
            StatisticsView().tabItem { Label("Statistiques", systemImage: "chart.bar") }
            SettingsView().tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .alert("Action impossible", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Compris") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { AppRuntime.shared.foreground() } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            AppRuntime.shared.foreground()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                store.perform { try store.reconcile() }
            }
        }
    }
}

struct TotalsView: View {
    let totals: TimeTotals
    var body: some View {
        LabeledContent("Travail", value: ParisTime.duration(totals.worked))
        LabeledContent("Présence", value: ParisTime.duration(totals.presence))
        LabeledContent("Pauses", value: ParisTime.duration(totals.pauses))
    }
}

struct GoalView: View {
    let worked: TimeInterval
    let target: TimeInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Objectif", value: "\(ParisTime.duration(worked)) / \(ParisTime.duration(target))")
            ProgressView(value: min(worked, target), total: max(1, target))
            Text(worked >= target ? "+\(ParisTime.duration(worked - target))" : "Reste : \(ParisTime.duration(target - worked))")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
