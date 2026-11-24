# Coach — consignes pour Claude

**Méthode de travail : lire `WORKFLOW.md` au début de chaque conversation** (issues comme seule
source, retour après chaque séance, cycle de développement, relectures, vérification avant le sport).

## Vie privée : rien de personnel sur le dépôt (priorité absolue)

Le dépôt est **public** (depuis le 18/11/2026). Tout ce qui y est poussé — fichiers, historique, messages de
commit, issues, pull requests, commentaires, branches `ci-logs` et `ci-captures` — doit pouvoir
être lu par n'importe qui.

- **Jamais** de données réelles de l'utilisateur : plan réel, export ou suivi, séances faites, chiffres de
  santé (FC, VFC, poids, allure, effort ressenti), dates de séances réelles, captures de son
  iPhone ou de sa montre, e-mail, adresse, lieu d'entraînement précis, appareils, clés d'accès.
- Exemples, tests et captures : uniquement des **données fictives** (`docs/exemple-plan.json`,
  mode démo). Ne jamais y recopier un plan ou un export que l'utilisateur a collé dans une conversation.
- Les retours de l'utilisateur (issues, PR) : décrire le problème de l'app, pas sa vie (« la séance passée
  reste marquée faite », pas « mardi j'avais mal au genou après 8 km à 5:40 »).
- Aucun secret dans le code : clés et adresses viennent des réglages de l'app, sur l'appareil
  (idéalement dans le trousseau), jamais en dur ni dans `project.yml`.
- **Avant chaque push**, relire `git diff --cached` et les nouveaux fichiers ; si un fichier
  ressemble à une donnée réelle (JSON de plan, export, capture d'appareil), ne pas le pousser
  et demander à l'utilisateur. `.gitignore` bloque déjà `plan-*.json`, `*export*.json`, `*suivi*.md`, `*.gpx`…, `perso/`.
- En cas de doute : ne pas pousser, demander.

## Une app réutilisable par d'autres

Coach est développée par et pour son propriétaire, mais doit pouvoir servir à d'autres personnes,
chacune avec ses propres réglages et son propre plan.

- **Pas de fonction d'IA pour le moment (#92)** : ni copier-coller vers une IA, ni « Mon propre coach ».
  Une couche IA facultative reviendra plus tard (#51), en suivant les règles ci-dessous.
- **Fonctions génériques.** Ne pas lier l'app à un outil précis : « Partager », « Copier »,
  « ton IA » ou « ton coach », pas « Claude ». L'utilisateur choisit l'IA ou l'app dans le menu
  de partage d'iOS. Quand le propriétaire parle de Claude, comprendre « l'IA » et proposer la
  version générique.
- **Rien de propre au propriétaire dans le code** : objectif, course, lieu, matériel, jours
  d'entraînement viennent du plan (`goals`, `notes`…) ou des réglages, jamais d'une chaîne en dur.
- Un service extérieur (une API d'IA, par exemple) reste une option désactivée par défaut,
  activée et configurée par l'utilisateur dans les réglages (clé dans le trousseau).

## Moteur de coaching local (#52)

- Le coach est un moteur de règles 100 % local, par modules, dans `Coach/Engine/` : pas d'IA en V1.
- Les règles et leurs valeurs de départ sont décidées dans les issues des modules : le code les suit,
  et toute valeur différente se discute d'abord dans l'issue.
- Chaque règle a un test automatique avec des données fictives.
- Avant la pull request d'un lot qui touche le moteur : agent `coach-reviewer` en plus du `code-reviewer`.

## Compilations GitHub Actions (gratuites en public, mais longues)

- Grouper les corrections et vérifier le code avant de pousser ; éviter les allers-retours.
- Un commit qui ne change que de la doc ou la config sans code : ajouter `[skip ci]`.
- `[captures]` seulement pour un vrai changement d'écran, et une fois le code prêt.

## Interface (iPhone et montre)

- **Avant toute modification d'interface, lire `DESIGN.md`** et suivre sa méthode :
  maquette → critique par l'agent `design-reviewer` (mode maquette) → validation du
  propriétaire → code → captures réelles → `design-reviewer` (mode conformité) et
  `code-reviewer` → pull request avec images.
- UX et ergonomie : suivre les skills `ios-design-guidelines` (iPhone) et
  `watchos-design-guidelines` (montre) dans `.claude/skills/`.
- Code SwiftUI : suivre le skill `swiftui-pro`. L'app vise iOS 17 et watchOS 10 : garder ces
  cibles, et mettre toute API plus récente sous `#available`.
- Thème visuel (couleurs, typo, ambiance sportive) : c'est `DESIGN.md` et `Shared/Theme.swift`
  qui décident, pas l'apparence par défaut proposée par les skills. Le thème doit quand même
  respecter leurs exigences d'accessibilité (contraste, Dynamic Type, pas de couleur seule).

## Conventions de code pour l'interface

- **Composants partagés d'abord.** Avant de créer un élément visuel (bouton, carte, ligne,
  pastille, titre de section), chercher s'il existe déjà (`Shared/Theme.swift`,
  `Coach/Collapsible.swift`, `CoachWatch/WatchButtons.swift`…) et le réutiliser.
- Un élément utilisé à deux endroits devient un composant commun, au lieu d'être recopié.
- Jamais de couleur, de taille de police, de rayon, de marge ou d'espace en dur dans une vue :
  passer par les jetons (`Space`, `Radius`, `Theme`) et les rôles de texte (`Font.text`, `.detail`…),
  voir la section « Design système » de `DESIGN.md`. Vérifier avec `python3 scripts/check-design.py`
  avant de pousser : pas de nouvelle ligne signalée dans les fichiers touchés.

## Captures automatiques

- Le build « Captures » ne tourne que si le message du commit contient `[captures]`
  (il est long : ne le lancer que quand l'interface a changé, une fois le code prêt).
- Lire le résultat : `git fetch origin ci-captures`, puis ouvrir les images du dossier au nom
  de la branche (les `/` deviennent des `-`), par exemple avec
  `git worktree add /tmp/captures origin/ci-captures`. `README.md` liste les écrans, les étapes
  sautées et l'audit d'accessibilité ; `journaux/` contient les erreurs des tests.
- Le mode démo (`Shared/DemoMode.swift`) n'existe qu'en Debug : plan d'exemple en mémoire,
  sans Santé ni synchronisation.
