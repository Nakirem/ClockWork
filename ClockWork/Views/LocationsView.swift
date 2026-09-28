import SwiftUI
import MapKit

struct LocationsView: View {
    @Environment(WorkStore.self) private var store
    @Environment(LocationService.self) private var service
    @State private var editing: WorkLocation?
    @State private var adding = false
    @State private var deleting: WorkLocation?
    var body: some View {
        NavigationStack {
            List {
                if store.locations.isEmpty {
                    ContentUnavailableView("Vos lieux", systemImage: "mappin.and.ellipse", description: Text("Ajoutez votre entreprise, votre école ou un autre lieu."))
                }
                ForEach(store.locations) { location in
                    Button { editing = location } label: {
                        HStack {
                            Image(systemName: location.category.symbol).foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name).foregroundStyle(.primary)
                                Text("\(location.category.title) · \(Int(location.radius)) m · \(location.automatic ? "Automatique" : "Manuel")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions { Button("Supprimer", role: .destructive) { deleting = location } }
                }
                Section {
                    Text("\(store.locations.filter(\.automatic).count) / 20 lieux automatiques. Les zones proches ou qui se chevauchent demandent une vérification manuelle du lieu.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lieux")
            .toolbar { Button { adding = true } label: { Label("Ajouter un lieu", systemImage: "plus") } }
            .sheet(isPresented: $adding) { LocationEditor(location: nil) }
            .sheet(item: $editing) { LocationEditor(location: $0) }
            .confirmationDialog("Supprimer ce lieu ? Toutes les présences sont conservées. Une présence active devra être terminée manuellement.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Supprimer le lieu", role: .destructive) {
                    if let id = deleting?.id, store.perform({ try store.deleteLocation(id) }) { service.syncRegions() }
                    deleting = nil
                }
            }
        }
    }
}

struct LocationEditor: View {
    @Environment(WorkStore.self) private var store
    @Environment(LocationService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LocationDraft
    @State private var camera: MapCameraPosition
    @State private var error: String?
    init(location: WorkLocation?) {
        let value = location.map(LocationDraft.init) ?? LocationDraft()
        _draft = State(initialValue: value)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude), latitudinalMeters: 1500, longitudinalMeters: 1500)))
    }
    private var coordinate: CLLocationCoordinate2D {
        // Numeric fields may temporarily contain out-of-range input while editing.
        CLLocationCoordinate2D(latitude: draft.latitude.isFinite ? min(90, max(-90, draft.latitude)) : 0,
                               longitude: draft.longitude.isFinite ? min(180, max(-180, draft.longitude)) : 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Lieu") {
                    TextField("Nom du lieu", text: $draft.name)
                    Picker("Catégorie", selection: $draft.category) { ForEach(LocationCategory.allCases) { Text($0.title).tag($0) } }
                    TextField("Adresse (facultative)", text: $draft.address, axis: .vertical)
                }
                Section("Touchez la carte pour placer le centre") {
                    MapReader { proxy in
                        Map(position: $camera) {
                            Marker(draft.name.isEmpty ? "Lieu" : draft.name, coordinate: coordinate)
                            MapCircle(center: coordinate, radius: draft.radius).foregroundStyle(.indigo.opacity(0.15)).stroke(.indigo, lineWidth: 2)
                        }
                        .onTapGesture { point in
                            if let selected = proxy.convert(point, from: .local) { draft.latitude = selected.latitude; draft.longitude = selected.longitude }
                        }
                    }.frame(height: 260)
                    Button(service.locating ? "Recherche de position…" : "Utiliser ma position actuelle") { service.locateOnce() }.disabled(service.locating)
                    if let message = service.lastError { Text(message).font(.caption).foregroundStyle(.orange) }
                    LabeledContent("Latitude") { TextField("Latitude", value: $draft.latitude, format: .number.precision(.fractionLength(6))).multilineTextAlignment(.trailing) }
                    LabeledContent("Longitude") { TextField("Longitude", value: $draft.longitude, format: .number.precision(.fractionLength(6))).multilineTextAlignment(.trailing) }
                    Text("La carte peut utiliser le service Apple Plans. Le pointage et les calculs fonctionnent sans carte ni serveur applicatif.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Zone de détection") {
                    Picker("Rayon", selection: $draft.radius) {
                        ForEach([50.0, 100, 150, 200, 300, 500, 1000], id: \.self) { Text("\(Int($0)) m").tag($0) }
                        if ![50.0, 100, 150, 200, 300, 500, 1000].contains(draft.radius) { Text("\(Int(draft.radius)) m (personnalisé)").tag(draft.radius) }
                    }
                    Stepper("Rayon personnalisé : \(Int(draft.radius)) m", value: $draft.radius, in: 50...1000, step: 10)
                    Toggle("Pointage automatique", isOn: $draft.automatic)
                    Text("150 à 300 m est un point de départ. Une petite zone peut être moins fiable, surtout en intérieur. L’heure détectée peut différer de l’arrivée réelle.").font(.caption).foregroundStyle(.secondary)
                    Text(service.status).font(.caption)
                }
            }
            .navigationTitle("Lieu").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                    do { try store.saveLocation(draft); service.syncRegions(); dismiss() }
                    catch { self.error = error.localizedDescription }
                } }
            }
            .onChange(of: service.currentCoordinate?.latitude) { _, _ in applyCurrentPosition() }
            .onChange(of: service.currentCoordinate?.longitude) { _, _ in applyCurrentPosition() }
            .alert("Lieu non enregistré", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Compris") { error = nil }
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled()
        }
    }
    private func applyCurrentPosition() {
        guard let coordinate = service.currentCoordinate else { return }
        draft.latitude = coordinate.latitude; draft.longitude = coordinate.longitude
        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
    }
}
