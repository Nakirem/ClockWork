# ClockWork

Application iPhone native de pointage personnel, en français, sans compte ni backend. SwiftUI, SwiftData, CoreLocation, MapKit et UserNotifications ; cible **iOS 17+**, projet pour **Xcode 16 ou ultérieur**, Swift en mode de langage 5 pour compatibilité.

## Ouvrir et lancer

**Depuis Windows, sans Mac personnel :** suivre le [guide GitHub Actions + Sideloadly](docs/SIDELOAD_WINDOWS.md). La chaîne fournie exécute les tests, compile pour iPhone puis produit `ClockWork-unsigned.ipa`. Sideloadly réalise ensuite la signature gratuite et l’installation sur l’iPhone. Aucun secret Apple n’est nécessaire dans GitHub.

1. Sur un Mac, ouvrir **ClockWork.xcodeproj** (pas Package.swift pour lancer l’app).
2. Choisir le schéma **ClockWork** et un simulateur iPhone iOS 17 ou ultérieur.
3. Lancer avec **⌘R**, exécuter les tests avec **⌘U**.
4. Sur iPhone physique, sélectionner votre équipe dans **Signing & Capabilities**, choisir un identifiant de bundle personnel si nécessaire et activer le mode développeur de l’iPhone.
5. Créer un lieu. Dans Réglages, autoriser la localisation pendant l’utilisation, puis Toujours ; activer Position précise et l’actualisation en arrière-plan. Les notifications sont facultatives et demandées séparément.

Le pointage manuel fonctionne sans autorisation de localisation. Les tuiles Apple Plans nécessitent généralement un accès réseau ; les données de pointage et leurs calculs sont locaux. Aucun package tiers n’est requis par l’application. La signature personnelle peut être soumise aux limites Apple de votre compte. L’icône de l’app provient de `assets/icon.PNG` (compilée en `AppIcon` via le catalogue d’assets). Les métadonnées App Store ne sont pas fournies : cette livraison cible l’usage personnel.

## AltStore Classic

L’application est distribuable via **AltStore Classic**. La source du dépôt est servie à l’adresse :

```
https://raw.githubusercontent.com/Nakirem/ClockWork/main/apps.json
```

Dans AltStore Classic : **Sources → + → Ajouter une source**, coller cette URL. L’app ClockWork apparaît avec son icône ; AltStore la re-signe avec votre compte Apple au moment de l’installation (compte gratuit : signature à renouveler tous les 7 jours dans AltStore).

**Publier une nouvelle version :**

1. Augmenter `MARKETING_VERSION` dans `scripts/generate_project.py`, puis régénérer avec `python3 scripts/generate_project.py` (ou modifier `project.pbxproj` directement). AltStore détecte les mises à jour via ce numéro (`CFBundleShortVersionString`).
2. Committer, puis pousser un tag `v*` (ex. `v1.1.0`) depuis `main` à jour.
3. GitHub Actions compile l’IPA, le publie en release GitHub, puis met automatiquement à jour `apps.json` (version, URL, taille, date) et le pousse sur `main`.

Le dépôt doit être **public** : AltStore télécharge `apps.json`, l’icône et l’IPA sans authentification.

## État de validation de cette livraison

Le projet a été créé sur **Windows sans Swift ni SDK iOS**. Les contrôles de structure (références Xcode, présence des sources, plist, assets, schéma) sont exécutables ici. **La compilation iOS, les XCTest et la vérification visuelle sur simulateur/iPhone n’ont pas été exécutés dans cet environnement.** Il ne s’agit donc pas d’une compilation certifiée. Voir `docs/VALIDATION.md` pour les résultats locaux et le protocole appareil.

La CI `.github/workflows/ios.yml` exécute `swift test`, les tests de packaging puis les tests de l’app sur un simulateur disponible. Sur un push ou lancement manuel réussi, elle produit ensuite une archive iPhone Release non signée et un IPA à récupérer dans les artefacts. Sur un tag `v*`, l’IPA est aussi publié en release GitHub et la source AltStore `apps.json` est mise à jour puis poussée sur `main` automatiquement. Sur une pull request, seuls les tests sont exécutés. L’état d’un lancement distant doit être vérifié dans GitHub Actions ; l’existence de cette configuration ne prouve pas que le build a réussi. En local sur Mac :

```sh
swift test
xcodebuild -list -project ClockWork.xcodeproj
xcodebuild -showdestinations -scheme ClockWork -project ClockWork.xcodeproj
xcodebuild test -project ClockWork.xcodeproj -scheme ClockWork \
  -destination 'platform=iOS Simulator,id=ID_DU_SIMULATEUR' \
  CODE_SIGNING_ALLOWED=NO
```

## Architecture

```text
ClockWork/
  App/           Composition, stockage local, lancement CoreLocation en arrière-plan
  Domain/        Valeurs métier, règles de validation, calculs purs, règles GPS
  Data/          Modèles SwiftData, transactions, snapshots et commandes métier
  Services/      Surveillance des zones, permissions, notifications locales
  Views/         Navigation, présentation, formulaires à brouillon
  Resources/     Info.plist, manifeste de confidentialité, couleur d’accent
Tests/
  Core/          Tests du domaine utilisables par Swift Package Manager
  Integration/   Tests SwiftData et transitions GPS dans la cible iOS
docs/            Décisions métier, cas limites, validation
scripts/         Génération reproductible et vérification du projet Xcode
```

Le domaine ne dépend que de Foundation. `WorkStore` expose des commandes et des snapshots immuables aux vues, sérialise les mutations sur le MainActor, valide avant écriture, sauvegarde explicitement et effectue un rollback en cas d’échec. Les formulaires travaillent sur des copies ; une modification concurrente de la présence par le GPS empêche l’écrasement d’anciennes données. Les vues ne manipulent pas de ModelContext.

`WorkLocation` définit une zone et mémorise son dernier état connu. `WorkSession` conserve arrivée, départ, sources distinctes, catégorie et identité/nom du lieu figés ; `BreakSession` est une entité liée avec suppression en cascade uniquement lorsque sa présence est supprimée. `AppSettings` est un singleton persistant. Supprimer un lieu n’a aucune cascade vers les présences. Aucune durée calculée n’est stockée.

Une panne d’ouverture de la base affiche une erreur ; elle ne crée jamais silencieusement une base vide. La base est dans Application Support/ClockWork, exclue de la sauvegarde système et configurée avec `cloudKitDatabase: .none`. Aucun entitlement iCloud n’est activé. Sans export V1, la désinstallation ou la perte de l’appareil peut faire perdre l’historique.

## Fonctionnalités

- Plusieurs lieux et catégories, carte tactile, coordonnées, position actuelle, rayons 50–1 000 m, activation indépendante, limite explicite de 20 lieux automatiques.
- Arrivées et départs manuels ; arrivées GPS et départ potentiel persistant avec délai de grâce de 10 minutes ; indication des passages courts et gestion des doublons.
- Plusieurs pauses, pause active, déjeuner configurable sans déduction implicite, ajout/correction/suppression des pauses.
- Création de présences oubliées, correction des heures/lieux, conservation de la provenance GPS, suppression confirmée des présences et des lieux.
- Historique par jour/semaine, navigation temporelle, détail ; statistiques jour/semaine/mois et par lieu/catégorie ; objectifs hebdomadaire (35 h initialement) et journalier optionnel.
- Notifications configurables par type, permissions expliquées, état de surveillance et accès aux réglages iOS.
- Toutes les dates affichées à Paris. Calcul en secondes réelles, découpe des périodes avec le calendrier Europe/Paris, gestion été/hiver et minuit.

## Choix du geofencing

`CLLocationManager` et `CLCircularRegion` permettent de conserver une cible iOS 17. Ces APIs historiques restent utilisables mais sont dépréciées dans les SDK Apple récents au profit des nouvelles APIs de conditions. Leur usage est isolé dans `LocationService`, pour permettre cette migration sans changer le domaine ou le stockage.

Une sortie enregistre son heure, sans fermer immédiatement la présence. Retour avant 10 minutes : annulation. Au-delà : clôture à l’heure de sortie, dès que du code peut à nouveau s’exécuter (événement pertinent ou premier plan). Au premier plan, une tâche vérifie l’échéance toutes les 15 secondes. Elle **n’est pas un minuteur d’arrière-plan**. Une notification différée annonce un départ *potentiel* et invite à vérifier ; elle ne prétend pas que la base a déjà été mise à jour. Les compteurs sont provisoirement arrêtés au départ potentiel.

Une pause manuelle prend la priorité sur les sorties. Une sortie longue sans pause puis un retour crée deux présences : le temps extérieur n’est pas travaillé. Un retour court annulé reste du travail sauf ajout explicite d’une pause. Ce choix évite d’inventer une pause déjeuner. Les passages très courts sont conservés et signalés, pas supprimés automatiquement. Les zones superposées ne peuvent pas démarrer deux présences.

La V1 n’active pas `UIBackgroundModes=location` ni `allowsBackgroundLocationUpdates` : ils servent au suivi continu, absent ici. La surveillance historique des régions sait réveiller l’app sans ce mode. Le service est recréé au lancement de l’application, y compris lors d’un réveil par CoreLocation. Le dernier état et le départ potentiel sont persistants. Voir `docs/ARCHITECTURE.md` pour les limites et cas particuliers.

## Évolutions

Les exports CSV/Excel/PDF pourront consommer les snapshots du domaine sans dépendre des vues. iCloud nécessitera une migration de schéma explicite (contraintes uniques/relations à adapter) et une politique de conflits ; aucune synchronisation implicite n’est préparée par un entitlement. Watch, widgets, Live Activities et Shortcuts pourront invoquer des commandes métier après extraction dans un module partagé et choix d’un App Group. Ces fonctionnalités sont volontairement absentes de la V1.

Pour régénérer le projet après ajout de fichiers : `python3 scripts/generate_project.py`. Le générateur et le projet produit sont livrés ; aucune installation XcodeGen n’est nécessaire.

## Références Apple consultées

- [Surveillance des régions et limite de 20 zones](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html)
- [Énergie et modes de localisation en arrière-plan](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)
- [Autorisation Always](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization())
- [Fiabilité des zones, rayons et relancement après fermeture — réponse Apple de mars 2026](https://developer.apple.com/forums/thread/818908)
- [Configuration du stockage SwiftData](https://developer.apple.com/documentation/swiftdata/modelconfiguration)

Les événements sont dépendants d’iOS et des conditions radio, pas une preuve certaine de présence physique ni un relevé d’heures garanti.
