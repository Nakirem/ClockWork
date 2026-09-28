import SwiftUI

struct SessionEditor: View {
    @Environment(WorkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let original: SessionRecord?
    @State private var draft: SessionRecord
    @State private var error: String?
    @State private var editingBreak: BreakRecord?
    init(record: SessionRecord?) {
        original = record
        let end = Date()
        _draft = State(initialValue: record ?? SessionRecord(start: end.addingTimeInterval(-8 * 3600), end: end, locationName: "", category: .work))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Présence · Europe/Paris") {
                    Picker("Lieu", selection: $draft.locationID) {
                        Text(draft.locationName.isEmpty ? "Choisir" : "\(draft.locationName) (historique)").tag(nil as UUID?)
                        if let id = draft.locationID, !store.locations.contains(where: { $0.id == id }) {
                            Text("\(draft.locationName) (supprimé)").tag(Optional(id))
                        }
                        ForEach(store.locations) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: draft.locationID) { _, id in
                        if let location = store.locations.first(where: { $0.id == id }) {
                            draft.locationName = location.name; draft.category = location.category
                        }
                    }
                    DatePicker("Arrivée", selection: $draft.start, in: ...Date())
                    Toggle("Présence terminée", isOn: Binding(get: { draft.end != nil }, set: { finished in
                        draft.end = finished ? Date() : nil
                        if finished {
                            for index in draft.breaks.indices where draft.breaks[index].end == nil { draft.breaks[index].end = draft.end }
                        }
                    }))
                    if draft.end != nil {
                        DatePicker("Départ", selection: Binding(get: { draft.end ?? Date() }, set: { draft.end = $0 }), in: ...Date())
                    }
                    Text("Les heures suivent Europe/Paris, même si l’iPhone change de fuseau.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Pauses") {
                    ForEach(draft.breaks.sorted { $0.start < $1.start }) { pause in
                        Button { editingBreak = pause } label: {
                            VStack(alignment: .leading) {
                                Text("\(pause.kind.title) · \(ParisTime.duration((pause.end ?? Date()).timeIntervalSince(pause.start)))")
                                Text("\(ParisTime.clock(pause.start)) → \(pause.end.map(ParisTime.clock) ?? "En cours")").font(.caption)
                            }
                        }
                        .swipeActions { Button("Supprimer", role: .destructive) { draft.breaks.removeAll { $0.id == pause.id } } }
                    }
                    Button("Ajouter une pause oubliée") {
                        let interval = ParisTime.lunch(on: draft.start, minute: store.settings.lunchStartMinute, duration: store.settings.lunchMinutes)
                        let start = min(max(interval.start, draft.start), draft.end ?? Date())
                        editingBreak = BreakRecord(start: start, end: min(start.addingTimeInterval(Double(store.settings.lunchMinutes * 60)), draft.end ?? Date()), kind: .lunch)
                    }
                    Toggle("Ne plus proposer de déjeuner pour cette présence", isOn: $draft.lunchDismissed)
                }
                Section("Aperçu") { TotalsView(totals: TimeAccounting.totals(draft, now: Date())) }
            }
            .navigationTitle(original == nil ? "Ajouter une présence" : "Modifier la présence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.fontWeight(.semibold) }
            }
            .sheet(item: $editingBreak) { pause in
                BreakEditor(record: pause) { result in
                    if let index = draft.breaks.firstIndex(where: { $0.id == result.id }) { draft.breaks[index] = result }
                    else { draft.breaks.append(result) }
                }
            }
            .alert("Enregistrement impossible", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Compris") { error = nil }
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled()
        }
    }
    private func save() {
        do {
            guard !draft.locationName.isEmpty else { throw WorkError.invalid("Choisissez un lieu. Créez-le d’abord dans Lieux si nécessaire.") }
            if let original, store.sessions.first(where: { $0.id == original.id }) != original {
                throw WorkError.invalid("Cette présence a changé pendant la modification (par exemple après un événement GPS). Annulez puis rouvrez-la pour utiliser ses nouvelles heures.")
            }
            try store.saveSession(draft)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct BreakEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BreakRecord
    let onSave: (BreakRecord) -> Void
    init(record: BreakRecord, onSave: @escaping (BreakRecord) -> Void) {
        _draft = State(initialValue: record); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $draft.kind) { ForEach(BreakKind.allCases) { Text($0.title).tag($0) } }
                DatePicker("Début", selection: $draft.start, in: ...Date())
                Toggle("Pause terminée", isOn: Binding(get: { draft.end != nil }, set: { draft.end = $0 ? max(draft.start, Date()) : nil }))
                if draft.end != nil {
                    DatePicker("Fin", selection: Binding(get: { draft.end ?? draft.start }, set: { draft.end = $0 }), in: ...Date())
                    Stepper("Durée : \(ParisTime.duration((draft.end ?? draft.start).timeIntervalSince(draft.start)))", value: Binding(get: { max(0, Int((draft.end ?? draft.start).timeIntervalSince(draft.start) / 60)) }, set: { draft.end = draft.start.addingTimeInterval(Double($0 * 60)) }), in: 0...1440)
                }
                TextField("Commentaire facultatif", text: $draft.comment, axis: .vertical)
                Text("L’ensemble des pauses sera validé lors de l’enregistrement de la présence.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Pause").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Valider") { onSave(draft); dismiss() } }
            }
        }
    }
}
