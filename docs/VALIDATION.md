# Validation

## État au 28 septembre 2026

- Environnement : Windows / PowerShell ; pas de `swift`, `xcodebuild` ou SDK iOS disponible.
- Projet Xcode généré avec sources de l’app, ressources, cible XCTest et schéma partagé.
- **Réussi localement** : `python scripts/validate_project.py` — références PBX, fichiers, plist, manifeste, assets et schéma XML.
- **Réussi localement** : `python scripts/check_syntax.py` — arbre syntaxique des 17 fichiers Swift (sources, tests et manifeste de package) avec tree-sitter-swift, et lecture OpenStep du projet Xcode. Ces vérifications ne font ni expansion des macros, ni contrôle des types, ni compilation avec le SDK Apple. Les outils Python de vérification sont isolés dans `.validation/`, ignoré par Git ; aucune dépendance n’est ajoutée à l’app.
- 35 méthodes XCTest fournies : 22 pour le domaine, 13 pour le store SwiftData.
- Parcours Sideloadly ajouté : six tests Python de packaging réussis localement (structure Payload, permissions de l’exécutable, checksum, rejet de simulateur, exécutable absent, identifiant non résolu et protection contre l’écrasement). Les fichiers de test sont fictifs et temporaires ; ils ne constituent pas une compilation iOS.
- Les XCTest, la compilation avec les SDK Apple, la CI et la validation visuelle ne sont pas exécutés ici. Le code a fait l’objet d’une revue statique ; toute affirmation de tests iOS réussis serait incorrecte.

## Couverture automatisée prévue

Calcul de plusieurs pauses, 37 minutes de déjeuner, absence de pause implicite, compteur durant une pause, correction d’une pause, traversée de minuit, semaines, dates Paris, journées de 23 h et 25 h, heure répétée, intervalles chevauchants invalides, clôture d’une pause active, objectifs École, doublons GPS, frontière des 10 minutes, gel pendant départ potentiel, retour court/long, transition entre sites, persistance dans un nouveau contexte, suppression d’un lieu sans perte d’historique, cascade des pauses, relation sans doublon, edit refusé sans mutation, provenance corrigée, limite de 20 zones, passage court.

## Protocole Xcode

1. Compiler en Debug puis Release pour simulateur avec le SDK installé ; exécuter tous les XCTest.
2. Vérifier l’absence d’avertissements de concurrence nouveaux sous la version Xcode choisie. Les dépréciations des anciennes APIs region monitoring dans les SDK récents sont documentées ; elles ne justifient pas l’activation du GPS continu.
3. Lancer sans lieux ni permissions, créer deux lieux, commencer/terminer manuellement, ajouter deux pauses, modifier et supprimer une pause, ajouter une présence historique.
4. Fermer/rouvrir l’app et vérifier la conservation des heures, pauses, préférences et noms historiques après suppression d’un lieu.
5. Vérifier tous les écrans avec le plus petit iPhone simulé, Dynamic Type, VoiceOver, modes clair/sombre et fuseau de l’iPhone hors Europe/Paris.
6. Tester les formulaires annulés et les erreurs : chevauchement, départ avant arrivée, pause hors présence, déjeuner habituel non contenu dans la présence, édition obsolète.
7. Vérifier les heures répétées lors du changement d’heure d’hiver dans les sélecteurs de dates ; les tests du domaine vérifient les instants absolus distincts.

## Protocole iPhone réel indispensable

1. Refus / autorisation pendant l’utilisation / Always, Position précise désactivée, services désactivés, Background App Refresh désactivé, notification refusée.
2. Un lieu avec rayon réaliste : approche, maintien dans la zone, sortie courte, sortie > 10 min, retour ; relever les délais réels sans supposer une précision à la minute.
3. Répéter avec app au premier plan, suspendue, fermée par l’utilisateur, puis téléphone redémarré et déverrouillé. Ne pas extrapoler un résultat de simulateur aux radios de l’iPhone.
4. Pendant une pause déjeuner manuelle : sortir, attendre, revenir, terminer la pause ; vérifier que la journée reste active et que le travail est arrêté.
5. Sortie sans pause manuelle : attendre la notification potentielle, ouvrir ensuite l’app ; départ clôturé à l’heure reçue, puis nouvelle présence au retour.
6. Deux zones superposées, passage bref, GPS intérieur, Wi-Fi coupé et mode économie d’énergie : vérifier les avertissements et la correction manuelle.
7. Démarrer une édition puis provoquer un événement GPS ; l’enregistrement obsolète doit être refusé.
8. Vérifier les catégories de notifications individuellement, y compris annulation d’un départ potentiel et désactivation des rappels déjà programmés.

## Limites acceptées en V1

Pas de reconstruction des événements manqués, pas de minuteur garanti en arrière-plan, pas d’heure automatique exacte garantie, pas d’export/synchronisation, pas de calcul de paie ou calendrier de congés. Une adresse peut être renseignée manuellement. La pause habituelle est proposée uniquement si son intervalle est inclus dans la présence ; sinon l’utilisateur passe par l’éditeur. Une sortie longue non qualifiée manuellement produit deux présences, pas une pause fabriquée. La validation terrain et le build Xcode restent nécessaires avant utilisation quotidienne.
