# Installer ClockWork depuis Windows — compte Apple gratuit

Ce parcours conserve l’application Swift native et utilise GitHub Actions uniquement pour compiler. Il ne nécessite ni Mac personnel, ni abonnement Apple Developer, ni publication App Store. L’historique de travail reste sur l’iPhone. Le code source est envoyé au dépôt GitHub privé choisi.

## 1. Produire l’application

Une fois les sources envoyées dans le dépôt GitHub :

1. Ouvrir l’onglet **Actions** du dépôt.
2. Choisir **ClockWork - tests et IPA Sideloadly**. Un envoi de code déclenche les tests et la fabrication ; **Run workflow** permet aussi un lancement manuel.
3. Attendre la coche verte. La chaîne vérifie le domaine, les tests iOS sur simulateur, puis compile une archive **iPhone physique / Release / arm64**.
4. En bas du résultat, télécharger l’artefact **ClockWork-Sideloadly-N**.
5. Extraire le ZIP téléchargé par GitHub. Il contient **ClockWork-unsigned.ipa**, son empreinte SHA-256, les informations de version et ce guide.

Le fichier `.ipa` doit encore être signé par Sideloadly. **Ne pas lui donner le ZIP extérieur téléchargé depuis GitHub.** Un build de simulateur ne peut pas être installé sur iPhone ; le script de packaging le refuse.

Les pull requests exécutent les tests uniquement. Les artefacts IPA sont conservés 7 jours et les résultats de tests 3 jours pour limiter le stockage. Un fichier IPA téléchargé n’est pas limité à ces 7 jours : cette durée est celle de sa disponibilité sur GitHub, distincte de l’expiration de sa signature Apple.

En dépôt privé, les compilations consomment le quota GitHub Actions et le stockage du compte. Aucun abonnement ou dépassement payant n’est configuré par ce projet. Vérifier le budget GitHub avant d’autoriser des dépenses supplémentaires. Les anciens lancements d’une même branche sont annulés quand un nouveau démarre.

## 2. Installer avec Sideloadly

1. Télécharger la version Windows depuis le [site officiel Sideloadly](https://sideloadly.io/).
2. Suivre les prérequis Windows indiqués par l’éditeur pour les composants Apple iTunes/iCloud. Leur installation est une étape locale distincte de la compilation.
3. Brancher l’iPhone par USB, le déverrouiller et accepter **Faire confiance à cet ordinateur** si demandé.
4. Ouvrir Sideloadly, sélectionner l’iPhone et déposer **ClockWork-unsigned.ipa**.
5. Saisir son compte Apple directement dans Sideloadly et effectuer soi-même les étapes d’authentification demandées. Aucun mot de passe Apple, code à deux facteurs ou certificat n’est requis dans GitHub ni dans cette conversation.
6. Lancer l’installation. Si iOS le demande, autoriser le profil développeur dans **Réglages → Général → VPN et gestion de l’appareil**, et activer le **Mode développeur** dans **Réglages → Confidentialité et sécurité**. Les intitulés peuvent varier selon iOS ; terminer le redémarrage et la confirmation sur l’iPhone si nécessaires.
7. Ouvrir ClockWork et vérifier d’abord une présence manuelle et une pause avant d’activer un lieu automatique.

Utiliser le même compte Apple et conserver le même identifiant d’application lors des mises à jour. Installer les nouvelles versions par-dessus l’existante, sans désinstaller ClockWork, afin de préserver son stockage local. La V1 n’a pas d’export ; une désinstallation efface potentiellement l’historique.

## 3. Renouveler la signature gratuite

Un compte gratuit signe l’application pour **7 jours** et reste soumis aux limites Apple de l’équipe personnelle. Activer le renouvellement automatique de Sideloadly. Le logiciel doit pouvoir s’exécuter et joindre l’iPhone ; pour le Wi-Fi, réaliser d’abord l’association USB et vérifier les prérequis du réseau local selon la documentation de Sideloadly.

Si la signature expire, renouveler l’installation puis rouvrir ClockWork pour vérifier les zones et corriger les heures éventuellement manquées. Le renouvellement n’a pas besoin d’une nouvelle compilation tant que le code ne change pas. Vérifier la date de validité dans Sideloadly, particulièrement avant une période sans accès au PC.

## 4. Vérifier le pointage automatique

Sur l’iPhone : créer un lieu réel, autoriser la localisation pendant l’utilisation puis **Toujours**, activer **Position précise** et l’actualisation en arrière-plan. Autoriser les notifications si souhaité. Tester une entrée et une sortie avec un rayon réaliste, puis vérifier l’historique. Les limites d’iOS restent les mêmes quelle que soit la méthode de compilation ; la signature gratuite ajoute une échéance à surveiller.

## Dépannage

- **Actions rouge** : ouvrir l’étape en échec ; aucune IPA n’est publiée si les tests ou la compilation échouent. Les journaux permettent de corriger le projet depuis Windows.
- **Pas d’artefact** : attendre la fin du lancement ; vérifier qu’il s’agit d’un push/lancement manuel réussi et que l’artefact n’a pas expiré.
- **Fichier non reconnu par Sideloadly** : extraire le ZIP GitHub et sélectionner le fichier dont l’extension est `.ipa`.
- **Erreur de signature/profil** : vérifier les limites du compte gratuit et les messages Sideloadly ; une compilation réussie ne prouve pas une installation réussie.
- **L’app ne s’ouvre plus après une semaine** : renouveler la signature, sans supprimer l’app.
- **Pointage GPS absent** : vérifier les réglages et le statut dans ClockWork ; corriger manuellement les événements manqués.

Références : [Sideloadly](https://sideloadly.io/), [téléchargement des artefacts GitHub](https://docs.github.com/en/actions/tutorials/store-and-share-data), [limites Apple Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account).
