import SwiftUI

struct HistoryView: View {
    @Environment(WorkStore.self) private var store
    @State private var anchor = Date()
    @State private var weekly = true
    @State private var adding = false
    var range: DateInterval { weekly ? ParisTime.week(anchor) : ParisTime.day(anchor) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Période", selection: $weekly) { Text("Jour").tag(false); Text("Semaine").tag(true) }.pickerStyle(.segmented)
                    HStack {
                        Button { anchor = ParisTime.shifted(anchor, days: weekly ? -7 : -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Période précédente")
                        Spacer()
                        Text(weekly ? "\(ParisTime.format(range.start, pattern: "d MMM")) – \(ParisTime.format(range.end.addingTimeInterval(-1), pattern: "d MMM yyyy"))" : ParisTime.label(anchor)).font(.subheadline)
                        Spacer()
                        Button { anchor = ParisTime.shifted(anchor, days: weekly ? 7 : 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Période suivante")
                    }.buttonStyle(.borderless)
                    Button("Revenir à aujourd’hui") { anchor = Date() }
                    TotalsView(totals: TimeAccounting.totals(store.sessions, within: range, now: Date()))
                }
                ForEach(0..<(weekly ? 7 : 1), id: \.self) { offset in
                    let day = ParisTime.shifted(range.start, days: offset)
                    let dayRange = ParisTime.day(day)
                    let records = store.sessions.filter { $0.start < dayRange.end && ($0.effectiveEnd ?? Date()) > dayRange.start }
                    if !records.isEmpty {
                        Section(ParisTime.label(day)) {
                            TotalsView(totals: TimeAccounting.totals(records, within: dayRange, now: Date()))
                            ForEach(records) { record in
                                NavigationLink { SessionDetailView(id: record.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(record.locationName).font(.headline)
                                        Text("\(ParisTime.format(record.start, pattern: "d MMM HH:mm")) → \(record.end.map { ParisTime.format($0, pattern: "d MMM HH:mm") } ?? "En cours")").font(.subheadline)
                                        Text("Travail ce jour : \(ParisTime.duration(TimeAccounting.totals(record, within: dayRange, now: Date()).worked))").foregroundStyle(.secondary)
                                        if record.needsReview { Label("Passage court à vérifier", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                                    }
                                }
                            }
                        }
                    }
                }
                if !store.sessions.contains(where: { $0.start < range.end && ($0.effectiveEnd ?? Date()) > range.start }) {
                    ContentUnavailableView("Aucune présence", systemImage: "calendar", description: Text("Ajoutez une journée oubliée avec le bouton +."))
                }
            }
            .navigationTitle("Historique")
            .toolbar { Button { adding = true } label: { Label("Ajouter une journée", systemImage: "plus") } }
            .sheet(isPresented: $adding) { SessionEditor(record: nil) }
        }
    }
}

struct SessionDetailView: View {
    @Environment(WorkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var editing: SessionRecord?
    @State private var deleting = false
    var body: some View {
        Group {
            if let record = store.sessions.first(where: { $0.id == id }) {
                List {
                    Section(ParisTime.label(record.start)) {
                        Label(record.locationName, systemImage: record.category.symbol)
                        LabeledContent("Arrivée", value: ParisTime.format(record.start, pattern: "d MMM HH:mm"))
                        LabeledContent("Départ", value: record.end.map { ParisTime.format($0, pattern: "d MMM HH:mm") } ?? "En cours")
                        TotalsView(totals: TimeAccounting.totals(record, now: Date()))
                        LabeledContent("Source arrivée", value: record.startSource.title)
                        if record.end != nil { LabeledContent("Source départ", value: record.endSource.title) }
                        if record.needsReview { Text("Passage court détecté. Vérifiez cette présence.").foregroundStyle(.orange) }
                    }
                    Section("Pauses") {
                        ForEach(record.breaks.sorted { $0.start < $1.start }) { pause in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(pause.kind.title) · \(ParisTime.duration((pause.end ?? Date()).timeIntervalSince(pause.start)))")
                                Text("\(ParisTime.format(pause.start, pattern: "d MMM HH:mm")) → \(pause.end.map { ParisTime.format($0, pattern: "d MMM HH:mm") } ?? "En cours")").font(.caption).foregroundStyle(.secondary)
                                if !pause.comment.isEmpty { Text(pause.comment).font(.subheadline) }
                            }
                        }
                        Button("Ajouter ou modifier les pauses") { editing = record }
                        if !record.breaks.contains(where: { $0.kind == .lunch }) && !record.lunchDismissed {
                            Button("+ Déjeuner habituel (\(store.settings.lunchMinutes) min)") { store.perform { try store.addUsualLunch(to: id) } }
                            Button("Aucune pause déjeuner") { store.perform { try store.dismissLunch(id) } }
                        }
                    }
                    Section { Button("Supprimer cette présence", role: .destructive) { deleting = true } }
                }
                .toolbar { Button("Modifier") { editing = record } }
            } else { ContentUnavailableView("Présence supprimée", systemImage: "clock") }
        }
        .navigationTitle("Détail").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { SessionEditor(record: $0) }
        .confirmationDialog("Supprimer la présence et ses pauses ?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if store.perform({ try store.deleteSession(id) }) { dismiss() } }
        }
    }
}
