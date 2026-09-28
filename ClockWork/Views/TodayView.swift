import SwiftUI

struct TodayView: View {
    @Environment(WorkStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var selectedLocation: UUID?
    @State private var editing: SessionRecord?
    @State private var showBreak = false
    @State private var showFinish = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                List {
                    if let active = store.active {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(active.locationName, systemImage: active.category.symbol).font(.headline)
                                Text("Depuis \(ParisTime.format(active.start, pattern: "d MMM à HH:mm")) · \(active.openBreak == nil ? "Travail" : "Pause")").foregroundStyle(.secondary)
                                Text("TEMPS TRAVAILLÉ").font(.caption).foregroundStyle(.secondary)
                                Text(ParisTime.duration(TimeAccounting.totals(active, now: timeline.date).worked))
                                    .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                                let totals = TimeAccounting.totals(active, now: timeline.date)
                                Text("Présence : \(ParisTime.duration(totals.presence)) · Pauses : \(ParisTime.duration(totals.pauses))").font(.subheadline)
                            }.padding(.vertical)
                            if let pause = active.openBreak {
                                Label("\(pause.kind.title) en cours · \(ParisTime.duration(timeline.date.timeIntervalSince(pause.start)))", systemImage: "pause.circle.fill")
                                Button("Finir la pause") { store.perform { try store.endBreak() } }.buttonStyle(.borderedProminent)
                            } else {
                                Button("Commencer une pause") { showBreak = true }.buttonStyle(.borderedProminent)
                            }
                            Button("Terminer ma journée", role: .destructive) { showFinish = true }
                            Button("Modifier les heures ou le lieu") { editing = active }
                        }
                        if let exit = active.pendingExit {
                            Section("Départ potentiel à \(ParisTime.clock(exit))") {
                                Text("Les compteurs sont provisoirement arrêtés à cette heure. Un retour en moins de 10 minutes annule le départ.").font(.subheadline)
                                Button("Confirmer ce départ") { store.perform { try store.confirmExit(active.id) } }
                                Button("Je reste / sortie temporaire") { store.perform { try store.cancelExit(active.id) } }
                                Button("C’était une pause : corriger") { editing = active }
                            }
                        }
                        if timeline.date.timeIntervalSince(active.start) > 16 * 3600 {
                            Section { Label("Présence ouverte depuis plus de 16 h. Vérifiez l’heure de départ et les pauses.", systemImage: "exclamationmark.triangle") }
                        }
                    } else {
                        Section("Prêt pour la journée") {
                            if store.locations.isEmpty {
                                Text("Ajoutez votre premier lieu dans l’onglet Lieux.").foregroundStyle(.secondary)
                            } else {
                                Picker("Lieu", selection: $selectedLocation) {
                                    Text("Choisir un lieu").tag(nil as UUID?)
                                    ForEach(store.locations) { Text($0.name).tag(Optional($0.id)) }
                                }
                                Button("Commencer ma journée") {
                                    if let selectedLocation { store.perform { try store.start(locationID: selectedLocation) } }
                                }.buttonStyle(.borderedProminent).disabled(selectedLocation == nil)
                            }
                        }
                    }
                    Section("Aujourd’hui · Europe/Paris") {
                        let today = ParisTime.day(timeline.date)
                        TotalsView(totals: TimeAccounting.totals(store.sessions, within: today, now: timeline.date))
                        if store.settings.dailyGoalEnabled {
                            GoalView(worked: TimeAccounting.totals(TimeAccounting.professional(store.sessions, includeSchool: store.settings.includeSchool), within: today, now: timeline.date).worked, target: Double(store.settings.dailyMinutes * 60))
                        }
                    }
                    if let record = store.sessions.first(where: { ParisTime.calendar.isDate($0.start, inSameDayAs: timeline.date) && !$0.lunchDismissed && !$0.breaks.contains(where: { $0.kind == .lunch }) }) {
                        Section("Aucune pause déjeuner enregistrée") {
                            Button("+ Pause déjeuner \(store.settings.lunchMinutes) min") { store.perform { try store.addUsualLunch(to: record.id) } }
                            Button("Modifier / saisir une autre durée") { editing = record }
                            Button("Aucune pause déjeuner pour cette présence") { store.perform { try store.dismissLunch(record.id) } }
                            Text("Aucune durée n’est déduite sans votre validation.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Cette semaine") {
                        GoalView(worked: TimeAccounting.totals(TimeAccounting.professional(store.sessions, includeSchool: store.settings.includeSchool), within: ParisTime.week(timeline.date), now: timeline.date).worked, target: Double(store.settings.weeklyMinutes * 60))
                    }
                    Section {
                        Label("Localisation automatique : \(location.status)", systemImage: "location")
                        if let message = store.geoMessage {
                            Text(message).foregroundStyle(.orange)
                            Button("J’ai vérifié") { store.geoMessage = nil }
                        }
                    }
                }
            }
            .navigationTitle("Aujourd’hui")
            .sheet(item: $editing) { SessionEditor(record: $0) }
            .confirmationDialog("Type de pause", isPresented: $showBreak, titleVisibility: .visible) {
                ForEach(BreakKind.allCases) { kind in Button(kind.title) { store.perform { try store.beginBreak(kind) } } }
            }
            .confirmationDialog("Terminer la présence à l’heure actuelle ? Toute pause active sera aussi terminée.", isPresented: $showFinish, titleVisibility: .visible) {
                Button("Terminer maintenant", role: .destructive) { if let id = store.active?.id { store.perform { try store.finish(id) } } }
            }
            .onAppear { if selectedLocation == nil { selectedLocation = store.locations.first?.id } }
        }
    }
}
