import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(WorkStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(NotificationService.self) private var notifications
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    var body: some View {
        NavigationStack {
            List {
                Section("Objectifs et déjeuner") {
                    LabeledContent("Objectif hebdomadaire", value: ParisTime.duration(Double(store.settings.weeklyMinutes * 60)))
                    if store.settings.dailyGoalEnabled { LabeledContent("Objectif journalier", value: ParisTime.duration(Double(store.settings.dailyMinutes * 60))) }
                    LabeledContent("Déjeuner habituel", value: "\(store.settings.lunchMinutes) min")
                    LabeledContent("École dans le total", value: store.settings.includeSchool ? "Oui" : "Non")
                    Button("Modifier mes préférences") { editing = true }
                }
                Section("Localisation automatique") {
                    Text(location.status)
                    Text("Votre position sert à détecter les entrées et sorties des lieux activés. Le suivi utilise les zones iOS, sans GPS continu. Autorisez d’abord la localisation pendant l’utilisation, puis « Toujours » pour les détections en arrière-plan.").font(.subheadline).foregroundStyle(.secondary)
                    if location.authorization == .notDetermined {
                        Button("Autoriser pendant l’utilisation") { location.requestWhenInUse() }
                    }
                    if location.authorization == .authorizedWhenInUse {
                        Button("Autoriser « Toujours »") { location.requestAlways() }
                    }
                    if !location.precise { Text("Activez Position précise dans les réglages de localisation de ClockWork.").foregroundStyle(.orange) }
                    if let error = location.lastError { Text(error).foregroundStyle(.orange) }
                    Button("Ouvrir les réglages iOS") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    Button("Vérifier les zones") { location.lastError = nil; location.refresh() }
                }
                Section("Notifications") {
                    Text(notifications.status)
                    Text("Recevez les arrivées, départs potentiels et rappels de déjeuner. Chaque type se règle dans vos préférences.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Autoriser les notifications") { Task { await notifications.request() } }
                    if let error = notifications.lastError { Text(error).foregroundStyle(.orange) }
                }
                Section {
                    NavigationLink("Fiabilité et fonctionnement") { ReliabilityView() }
                    NavigationLink("Confidentialité") { PrivacyView() }
                    LabeledContent("Fuseau de référence", value: "Europe/Paris")
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $editing) { SettingsEditor(settings: store.settings) }
            .task { location.refresh(); await notifications.refresh() }
        }
    }
}

struct SettingsEditor: View {
    @Environment(WorkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SettingsDraft
    @State private var error: String?
    init(settings: AppSettings) { _draft = State(initialValue: SettingsDraft(settings)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Objectifs") {
                    Stepper("Semaine : \(ParisTime.duration(Double(draft.weeklyMinutes * 60)))", value: $draft.weeklyMinutes, in: 15...10080, step: 15)
                    LabeledContent("Minutes par semaine") { TextField("Minutes", value: $draft.weeklyMinutes, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    Toggle("Objectif journalier", isOn: $draft.dailyGoalEnabled)
                    if draft.dailyGoalEnabled { Stepper("Jour : \(ParisTime.duration(Double(draft.dailyMinutes * 60)))", value: $draft.dailyMinutes, in: 15...1440, step: 15) }
                    Toggle("Compter l’école dans les heures professionnelles", isOn: $draft.includeSchool)
                }
                Section("Déjeuner habituel") {
                    DatePicker("Heure de début", selection: Binding(get: { ParisTime.lunch(on: Date(), minute: draft.lunchStartMinute, duration: draft.lunchMinutes).start }, set: {
                        let components = ParisTime.calendar.dateComponents([.hour, .minute], from: $0)
                        draft.lunchStartMinute = (components.hour ?? 12) * 60 + (components.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
                    Picker("Durée", selection: $draft.lunchMinutes) {
                        ForEach([30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                        if ![30, 45, 60, 90].contains(draft.lunchMinutes) { Text("\(draft.lunchMinutes) min").tag(draft.lunchMinutes) }
                    }
                    Stepper("Durée personnalisée : \(draft.lunchMinutes) min", value: $draft.lunchMinutes, in: 1...480)
                    Text("Ce réglage prépare un raccourci. Il ne déduit jamais de pause automatiquement.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    Toggle("Arrivée détectée", isOn: $draft.notifyArrival)
                    Toggle("Départ potentiel et confirmé", isOn: $draft.notifyDeparture)
                    Toggle("Début de pause", isOn: $draft.notifyBreakStart)
                    Toggle("Fin de pause", isOn: $draft.notifyBreakEnd)
                    Toggle("Déjeuner non enregistré", isOn: $draft.notifyMissingLunch)
                }
            }
            .navigationTitle("Préférences").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                    do { try store.saveSettings(draft); dismiss() } catch { self.error = error.localizedDescription }
                } }
            }
            .alert("Préférences non enregistrées", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Compris") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

struct ReliabilityView: View {
    var body: some View {
        List {
            Section("Arrivées") { Text("iOS détecte le franchissement de la zone, avec une précision et un délai variables. Une entrée crée une présence si aucune autre n’est active. Les passages courts sont signalés à vérifier dans l’historique. Deux sites qui se chevauchent peuvent nécessiter de choisir le lieu manuellement.") }
            Section("Sorties") { Text("La sortie devient un départ potentiel persistant. Un retour dans les 10 minutes l’annule. Après ce délai, le prochain événement ou l’ouverture de l’app clôture la présence à l’heure de sortie détectée. Une notification différée invite à vérifier ; elle ne prouve pas que l’app a pu s’exécuter. Les compteurs sont provisoirement arrêtés pendant cette attente.") }
            Section("Pauses à l’extérieur") { Text("Lancez une pause avant de sortir : elle reste ouverte jusqu’à votre action et empêche la clôture automatique. Sans pause manuelle, une longue sortie et un retour créent deux présences ; l’intervalle extérieur n’est pas compté comme travail. Une sortie courte annulée compte comme présence travaillée : ajoutez une pause si nécessaire.") }
            Section("Disponibilité") { Text("Autorisez Toujours, Position précise et l’actualisation en arrière-plan. Après redémarrage, déverrouillez l’iPhone. iOS peut relancer l’app pour une zone même après fermeture, mais les événements peuvent être retardés ou manqués selon les conditions radio, l’alimentation et les réglages. L’app ne peut ni garantir une heure exacte, ni reconstruire une position passée. Vérifiez vos pointages après une interruption.") }
            Section("Oublis") { Text("Une pause ou une présence oubliée ne reçoit pas une durée inventée. Une présence de plus de 16 h est signalée ; corrigez son départ et ses pauses dans l’historique. L’enregistrement ferme une pause active au départ choisi si elle reste dans les horaires.") }
        }.navigationTitle("Fiabilité").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Sur votre iPhone") { Text("ClockWork conserve les lieux, présences, pauses et préférences dans une base locale. Aucun compte, serveur applicatif, suivi publicitaire ou outil d’analyse n’est intégré. L’app ne vend ni ne transmet votre historique ou votre position à un serveur applicatif.") }
            Section("Localisation et carte") { Text("Les coordonnées servent à définir les zones surveillées par iOS. Le GPS continu n’est pas utilisé. La carte est fournie par Apple Plans et peut charger des données auprès d’Apple. Vous pouvez saisir les coordonnées directement et pointer manuellement sans utiliser la carte.") }
            Section("Sauvegarde") { Text("La base locale est exclue de la sauvegarde système et aucune synchronisation iCloud n’est activée. La désinstallation ou la perte de l’iPhone peut donc faire perdre vos données. L’export et la synchronisation sont prévus pour une version future.") }
            Section("Votre contrôle") { Text("Chaque présence et pause peut être corrigée ou supprimée. Supprimer un lieu conserve les présences existantes. Vous pouvez désactiver la localisation et les notifications dans les réglages iOS à tout moment.") }
        }.navigationTitle("Confidentialité").navigationBarTitleDisplayMode(.inline)
    }
}
