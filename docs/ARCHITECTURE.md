# Architecture et règles de la V1

## Flux d’écriture

View (brouillon) → WorkStore (MainActor) → validation des valeurs → ModelContext privé sans autosave → save → nouveaux snapshots.

CoreLocation (delegate sur la run loop principale) → WorkStore.boundary → transaction unique du nouvel état de zone et des présences → notifications après sauvegarde.

Les services et l’UI partagent une instance du store créée par AppRuntime. Les erreurs de sauvegarde annulent les mutations et remontent dans l’app ; aucune notification de succès n’est envoyée avant la sauvegarde. L’historique est chargé intégralement en V1, adapté à l’usage personnel ; une pagination sera à ajouter pour des volumes importants.

## États

| État | Actions et transition |
|---|---|
| Aucune présence ouverte | Début manuel ou entrée GPS → travail |
| Travail | Début pause → pause ; fin manuelle → terminée ; sortie GPS → départ potentiel |
| Pause | Fin pause → travail ; fin présence → ferme aussi la pause ; sortie GPS → reste en pause |
| Départ potentiel | Retour < 10 min → travail ; confirmation → terminée ; échéance traitée au prochain réveil → terminée à l’heure détectée |
| Terminée | Nouvelle entrée GPS → nouvelle présence ; modification contrôlée possible |

Une présence peut être rouverte dans l’éditeur si aucune autre n’est active et si cela ne chevauche pas une autre présence. Les intervalles métier sont semi-ouverts pour accepter deux sites successifs à la même heure. Les pauses peuvent avoir une durée nulle lors d’une correction, mais ne peuvent se chevaucher. Les dates futures sont refusées.

## Dates et durées

Les `Date` représentent des instants absolus, pas une heure locale sans fuseau. Le calendrier ISO Europe/Paris détermine les limites de jours et de semaines (lundi). Le calcul coupe séparément la présence et chaque pause aux bornes de la période ; l’union des pauses empêche une double soustraction, même avec des données incorrectes importées ultérieurement. Le décompte reste précis à la seconde ; l’affichage tronque aux minutes sans arrondi de paie. Une journée de changement d’heure peut durer 23 h ou 25 h. La moyenne porte sur les jours civils ayant une présence dans la période.

Les heures répétées au passage à l’heure d’hiver restent deux instants distincts en stockage. Le sélecteur natif choisit l’instant selon son comportement iOS ; vérifier ces horaires sur appareil lors de corrections autour de 02 h. Les objectifs comparent la durée professionnelle déjà enregistrée à l’objectif entier de la période, sans déduire arbitrairement des congés, jours fériés ou horaires de contrat. Aucun objectif mensuel n’est inventé.

## Déduplication et départ différé

Chaque zone conserve `unknown`, `inside` ou `outside` ainsi que la date du dernier changement traité. Une entrée identique ne recrée pas de présence. Une sortie identique ne déplace jamais l’heure de départ potentiel ; elle peut traiter une échéance déjà due. Les états et les données métier sont écrits dans la même transaction. La sauvegarde d’une correction manuelle annule le départ potentiel et sa notification. Une clôture manuelle alors que la zone reste `inside` n’est pas annulée par les requêtes répétées de son état.

La première résolution `inside` d’une zone activée peut créer une arrivée à l’heure actuelle, jamais dans le passé. Une géométrie de zone modifiée réinitialise son état : la réinscription est assimilée à une nouvelle résolution. Une zone désactivée ou supprimée annule son départ potentiel, conserve la présence ouverte et requiert un départ manuel.

Un départ est traité à l’heure de réception CoreLocation : les callbacks de franchissement historiques ne donnent pas l’heure exacte du franchissement physique. Aucune position ancienne n’est reconstituée. Aucun timer, notification locale ou BGTask ne garantit une exécution à l’échéance exacte.

## Cas particuliers

| Cas | Comportement |
|---|---|
| Arrivée/sortie GPS répétée | Déduplication persistante, première heure préservée |
| Passage rapide | Filtrage déjà réalisé par iOS ; présence < 3 min marquée à vérifier lors de la clôture |
| Deux sites le même jour | Présences distinctes ; entrée sur B clôture le départ potentiel de A à son heure initiale |
| Zones simultanées sans sortie de A | Une seule présence ; message demandant vérification, aucun remplacement du lieu en cours |
| Retour court | Départ annulé ; ajouter une pause si le temps doit être déduit |
| Retour après 10 min | Première présence clôturée, nouvelle présence, intervalle extérieur exclu |
| Pause manuelle à l’extérieur | Maintenue jusqu’à action ; retour GPS ne termine pas silencieusement la pause |
| Fin de pause encore à l’extérieur | Nouveau départ potentiel à la fin de la pause |
| Aucune pause | Aucune soustraction ; rappel facultatif, action Aucune pause |
| Déjeuner 37 min au lieu de 60 | Déduire 37 min réelles ; raccourci de 60 min soumis à validation des horaires |
| Pause oubliée ouverte | Travail arrêté jusqu’à correction ; clôture manuelle ferme aussi la pause |
| Présence oubliée | Avertissement après 16 h, aucune heure de départ inventée |
| Minuit / DST / voyage | Instants absolus et découpage à Paris |
| Modification ancienne | Brouillon complet validé contre toutes les présences, recalcul immédiat après sauvegarde |
| Modification et événement GPS concurrent | Refus d’écraser la version modifiée entre-temps |
| Redémarrage | Réouverture de la base, reconnexion aux régions ; disponibilité après déverrouillage sous contrôle iOS |
| Localisation coupée / réduite / refusée | État explicite, suivi manuel disponible ; pas de reconstruction des événements manqués |
| Suppression d’un lieu | Snapshots historiques conservés, zone désinscrite, fin manuelle si présence active |
| Échec du stockage | Erreur visible, rollback, jamais de remise à zéro automatique |

## Confidentialité et permissions

Les textes de permission décrivent un usage individuel et volontaire. Demandes uniquement après un bouton explicatif ; aucune sollicitation automatique au lancement. L’autorisation notifications ne conditionne jamais la sauvegarde. Position précise et Always sont nécessaires au mode automatique retenu. L’état Background App Refresh est visible. Les 20 zones sont choisies explicitement par l’utilisateur ; aucune sélection silencieuse de proximité.

La carte Apple est facultative pour sélectionner les coordonnées ; l’adresse lisible peut être saisie manuellement. Il n’y a pas de recherche d’adresse ou de géocodage réseau caché. Seules les coordonnées des lieux sont conservées, pas une trace de déplacements. La base exclut la sauvegarde système. Le manifeste de confidentialité n’annonce aucune collecte ni suivi publicitaire.

## Concurrence et évolutions

Le ModelContext n’est jamais envoyé à un acteur ou une tâche détachée. Les delegates CoreLocation sont servis sur la run loop de création, principale ; le delegate de présentation des notifications est `nonisolated` et ne touche pas le stockage. Les réponses asynchrones de notifications reviennent sur le MainActor pour publier une erreur.

Les modèles V1 n’annoncent pas de fausse compatibilité iCloud. Une évolution de schéma devra introduire VersionedSchema/SchemaMigrationPlan avec des tests sur une copie d’une base V1, avant modification des propriétés persistées. Ne pas modifier les noms/types des modèles existants sans migration. Les futures extensions devront partager les règles et les commandes, pas écrire directement dans les modèles depuis leurs vues.
