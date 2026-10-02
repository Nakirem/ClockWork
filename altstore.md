📋 Cahier des charges : Automatisation du déploiement et de la source AltStore
Objectif : Mettre en place un pipeline entièrement automatisé sur GitHub permettant, à chaque nouvelle version de l'application, de compiler l'IPA, de générer/mettre à jour le fichier de source JSON pour AltStore Classic, et de le publier. L'utilisateur final pourra alors ajouter l'URL de cette source dans AltStore pour installer et mettre à jour l'application.

Contexte technique : Le code source est hébergé sur GitHub. La compilation de l'IPA est déjà gérée par un workflow GitHub Actions existant (ou doit être créée).

1. Fichier de source AltStore (repo.json ou apps.json)
Tâche : Créer un fichier JSON statique qui servira de source pour AltStore. Ce fichier doit être hébergé sur une branche publique de votre dépôt (par exemple, gh-pages ou main).

Spécifications :

Le fichier doit respecter le schéma officiel d'AltStore. Voici un exemple minimal pour une application :

json
{
  "name": "Nom de ma Source",
  "subtitle": "Description courte",
  "description": "Description complète de la source.",
  "iconURL": "https://example.com/icon.png",
  "headerURL": "https://example.com/header.png",
  "website": "https://example.com",
  "tintColor": "#F54F32",
  "apps": [
    {
      "name": "Nom de mon application",
      "bundleIdentifier": "com.monnom.monapp",
      "developerName": "Mon Nom",
      "subtitle": "Sous-titre de l'app",
      "localizedDescription": "Description de l'application.",
      "iconURL": "https://example.com/app-icon.png",
      "versions": [
        {
          "version": "1.0",
          "buildVersion": "1",
          "date": "2026-10-02",
          "localizedDescription": "Première version.",
          "downloadURL": "https://github.com/votre-user/votre-repo/releases/download/v1.0/MonApp.ipa",
          "size": 79821,
          "minOSVersion": "14.0"
        }
      ]
    }
  ]
}
Points clés :

bundleIdentifier doit correspondre exactement à celui de votre application.

Le tableau versions doit être ordonné du plus récent au plus ancien. AltStore détecte les mises à jour en comparant la première entrée (index 0) avec la version installée.

downloadURL doit pointer directement vers le fichier .ipa hébergé (par exemple, dans les assets d'une release GitHub).

size doit être la taille du fichier en octets.

version et buildVersion doivent correspondre à CFBundleShortVersionString et CFBundleVersion de votre app.

Livrable : Un fichier repo.json (ou apps.json) à la racine d'une branche dédiée, prêt à être servi via une URL brute GitHub (https://raw.githubusercontent.com/...).

2. Workflow GitHub Actions : Mise à jour automatique de la source
Tâche : Créer un workflow qui se déclenche automatiquement après la publication d'une nouvelle release et qui met à jour le fichier repo.json.

Déclencheur :

yaml
on:
  release:
    types: [published]
Ou, si vous préférez, après la fin réussie du workflow de build :

yaml
on:
  workflow_run:
    workflows: ["Nom du workflow de build IPA"]
    types: [completed]
Étapes du workflow :

Checkout du dépôt : Récupérer le code source et le fichier repo.json existant.

Récupération des métadonnées de la release : Utiliser l'API GitHub (via gh CLI ou actions/github-script) pour obtenir :

Le tag de la release (ex: v1.2.3).

L'URL de téléchargement de l'asset .ipa.

La taille du fichier .ipa.

Extraction de la version : Récupérer CFBundleShortVersionString et CFBundleVersion depuis le fichier project.pbxproj ou Info.plist de votre projet. De nombreux projets utilisent un script pour cela (ex: MARKETING_VERSION extrait de project.pbxproj).

Mise à jour du JSON : Utiliser un script (Python, Node.js ou shell) pour :

Lire le fichier repo.json existant.

Ajouter une nouvelle entrée au début du tableau versions de l'application avec les informations extraites.

Écrire le fichier mis à jour.

Commit et Push : Committer le repo.json mis à jour et le pousser vers la branche qui héberge la source (ex: main ou gh-pages). Cela peut être fait avec actions/checkout et des commandes git.

Outils recommandés pour le script de mise à jour :

altgen (Python) : Un package pip qui génère un fichier apps.json pour AltStore à partir des assets IPA des releases GitHub. Vous pouvez l'intégrer dans un workflow en installant altgen et en l'exécutant.

altstore-github (Node.js) : Un package npm qui construit un dépôt AltStore à partir des données des releases GitHub. Il peut être exécuté avec npx pour générer le JSON.

Script personnalisé : Vous pouvez également écrire un script Python ou Node.js qui utilise l'API GitHub pour récupérer les informations et manipuler le JSON. De nombreux projets open source le font, par exemple StikJIT avec son script update_json.py.

Livrable : Un fichier .github/workflows/update-altstore-source.yml qui automatise entièrement la mise à jour de la source.

3. Workflow GitHub Actions : Build de l'IPA (si non existant)
Tâche : Si vous n'avez pas encore de workflow qui compile votre application en IPA, vous devez en créer un.

Spécifications :

Runner : Utilisez macos-latest car la compilation iOS nécessite Xcode.

Compilation non signée : Désactivez la signature de code pendant la compilation (CODE_SIGN_IDENTITY="", CODE_SIGNING_REQUIRED=NO, CODE_SIGNING_ALLOWED=NO). L'IPA sera re-signé par AltStore lors de l'installation.

Packaging : Après la compilation, créez manuellement une structure Payload/ contenant le fichier .app, puis compressez le tout en un fichier .ipa (par exemple, avec zip -r).

Publication : Créez une release GitHub et uploadez l'IPA en tant qu'asset. Vous pouvez utiliser l'action softprops/action-gh-release ou actions/upload-release-asset.

Livrable : Un fichier .github/workflows/build-ipa.yml qui compile et publie l'IPA.

4. Publication de la source
Tâche : S'assurer que le fichier repo.json est accessible publiquement via une URL stable.

Actions :

Le workflow de mise à jour doit pousser le repo.json vers une branche publique de votre dépôt (par exemple, main ou une branche dédiée gh-pages).

L'URL finale de la source sera :
https://raw.githubusercontent.com/votre-user/votre-repo/branche/repo.json

Vous pouvez également utiliser GitHub Pages pour héberger le fichier avec une URL plus propre.

5. Test et validation
Tâche : Vérifier que le pipeline fonctionne de bout en bout.

Étapes de validation :

Poussez une modification de version dans votre code (augmentez CFBundleShortVersionString et CFBundleVersion).

Créez une nouvelle release GitHub ou déclenchez manuellement le workflow de build.

Attendez que le workflow de mise à jour de la source s'exécute.

Vérifiez que le fichier repo.json sur GitHub contient bien une nouvelle entrée en première position avec la nouvelle version et l'URL de l'IPA.

Sur votre iPhone, ouvrez AltStore, ajoutez l'URL de la source (si ce n'est pas déjà fait), et vérifiez qu'une mise à jour est proposée pour votre application.

Livrable : Un rapport de validation confirmant le bon fonctionnement du pipeline.

