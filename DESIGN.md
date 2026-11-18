# DESIGN.md — règles d'interface de Coach (montre + iPhone)

À lire avant toute modification d'interface, sur l'iPhone comme sur la montre.

## Qui décide de quoi

- **UX et ergonomie → les skills** (`.claude/skills/ios-design-guidelines` et
  `.claude/skills/watchos-design-guidelines`, tirés des guides d'Apple) : navigation,
  hiérarchie, tailles des cibles, Dynamic Type, accessibilité, contraste, Digital Crown,
  affichage permanent, haptique. Ils priment sur nos habitudes.
- **Thème visuel → nous** (section « Identité visuelle » et `Shared/Theme.swift`) : couleurs,
  typographie, ambiance. Coach garde un **design sportif** qui lui est propre.
  Les règles des skills sur l'apparence par défaut (couleurs système, `systemBackground`,
  un seul accent, cartes natives) ne s'appliquent pas au thème.
- **Le thème doit quand même respecter** les exigences d'accessibilité des skills : contraste
  d'au moins 4,5:1 pour le texte, jamais d'information portée par la couleur seule, Dynamic
  Type, « Texte en gras », « Augmenter le contraste ».

## Méthode pour chaque écran

1. **Maquette validée.** Avant de coder, proposer une maquette sur un canevas (comme
   « Coach — maquette accueil iPhone »), au format décrit plus bas, et attendre la validation
   du propriétaire.
2. **Coder avec des composants partagés.** Réutiliser ce qui existe (`Theme`, `Eyebrow`,
   `.card()`, `Collapsible`, styles de boutons). Un élément visuel utilisé à deux endroits
   devient un composant dans `Shared/` ou un fichier commun, au lieu d'être recopié.
   Suivre les skills `ios-design-guidelines`, `watchos-design-guidelines` et `swiftui-pro`.
3. **Captures réelles.** Mettre `[captures]` dans le message du dernier commit : le build
   « Captures » photographie les écrans clés (iPhone, petit iPhone, grande et petite montre,
   très grand texte) avec le plan de démo et lance l'audit d'accessibilité d'Apple.
   Résultat : branche `ci-captures`, dossier au nom de la branche (`README.md` montre tout).
   Un nouvel écran s'ajoute dans `CoachUITests/CoachCaptures.swift` ou
   `CoachWatchUITests/WatchCaptures.swift`.
4. **Relecture indépendante.** Lancer l'agent `design-reviewer` (`.claude/agents/`) sur les
   captures : il compare le rendu réel à la maquette et à ce fichier, sans avoir écrit le
   code. Corriger les écarts, puis refaire les captures si le rendu a changé.
5. **Pull request avec images.** Lister les écrans touchés et joindre les captures clés
   (liens vers `ci-captures`), avec les écarts restants assumés. Le propriétaire valide sur les images.
6. **Retour d'usage.** Chaque remarque du propriétaire après un test sur son iPhone ou sa montre
   devient une règle dans ce fichier, pour ne pas refaire la même erreur.
7. Si un choix va contre ce fichier, le dire et le justifier.

## Identité visuelle (thème sportif, à affiner)

Direction : **sportif, énergique, lisible en plein effort**. Le thème actuel de
`Shared/Theme.swift` sert de base tant qu'on n'a pas validé une nouvelle version.

### Base actuelle
- Fond sombre `Theme.bg` #0B0F14, cartes `Theme.card` / `Theme.card2`, bordures `Theme.line`.
- Texte : `Theme.text` pour l'essentiel, `Theme.muted` pour le secondaire.
- Accents, chacun avec **un sens fixe** :
  - citron vert `Theme.accent` #C6F432 : circuits, action principale, progression ;
  - turquoise `Theme.teal` #2DD4BF : renforcement ;
  - orange `Theme.warm` #FF7A45 : course, muscles sollicités, intensité.
- Typo arrondie (`design: .rounded`), titres très gras avec `Font.display`, petits titres
  avec `Eyebrow`. Cartes arrondies avec `.card()`.

### Règles du thème
- Jamais de couleur en dur dans une vue : l'ajouter à `Theme` si elle manque.
- Sur un même écran : un accent dominant, deux au maximum.
- La couleur s'accompagne toujours d'une icône (`Theme.icon(for:)`) ou d'un mot.
- Tailles de texte via les styles (`.title`, `.body`…) avec `design: .rounded`, pour garder
  le style sportif **et** Dynamic Type. Pas de tailles fixes pour le texte courant.
- Vérifier le contraste de chaque couleur de texte sur son fond (4,5:1 minimum).
- Icônes : SF Symbols, même graisse sur un écran.

### À décider
- Sombre uniquement (actuel) ou aussi un mode clair ?
- Garder les trois accents ou les resserrer ?
- Faut-il une typo plus marquée pour les titres et les chiffres ?

## Principes généraux

- Une information principale par écran. Le reste est secondaire et plus discret.
- Composants natifs SwiftUI d'abord (comportement et accessibilité), habillés avec `Theme`.
- Trois niveaux de texte maximum par écran.
- Cibles tactiles d'au moins 44 pt, contraste suffisant, libellés VoiceOver sur les icônes.

## Apple Watch

- **Lisible en moins de 2 secondes, en mouvement.** Si ça demande de lire une phrase, c'est trop.
- Une action principale par écran : gros bouton pleine largeur en bas.
- 3 ou 4 éléments maximum à l'écran.
- Chiffres très grands, arrondis et à chasse fixe (`.monospacedDigit()`) pour les chronos.
- **Digital Crown** pour ajuster poids et répétitions, pas de petits boutons + / −.
- Navigation cohérente et prévisible : 2 niveaux maximum, pages verticales pour le détail.
- Pendant l'effort : nom de l'exercice, série x/y, chrono ou répétitions. Rien d'autre.
- Pendant le repos : compte à rebours géant + nom de l'exercice suivant. Pas d'animation, pas
  de texte d'explication.
- **Un seul « Commencer » par séance.** Il lance en même temps le chrono et le premier exercice,
  puis tout s'enchaîne. Avant le départ, c'est le seul bouton visible ; le chrono ne tourne pas
  avant cet appui.
- **Couleur plein écran** (teinte du type de séance) pour signaler l'état d'un coup d'œil :
  effort, repos, terminé.
- Retour haptique aux transitions (début, fin de série, fin de repos).
- Vérifier l'affichage permanent (luminosité réduite, `isLuminanceReduced`).
- **Pas d'explications sur la montre** (pas de « Comment faire ? ») : elles restent sur l'iPhone.
- **Commandes sur une page à part** (pause, passer, +30 s, terminer, FC, durée) : on y arrive en
  glissant vers la droite, comme dans l'app Exercice. Les écrans d'effort et de repos n'ont pas
  d'autre bouton que l'action de l'étape (« Série faite »).
- **Lancer depuis l'iPhone** : « Démarrer sur la montre » ouvre Coach sur la montre, sur la séance,
  prête. Rien ne démarre avant le « Commencer » de la montre.
- Doit rester utilisable en courant, en sueur, avec des doigts mouillés.

## iPhone

- Accueil : la séance du jour en haut, dans une grande carte, avec l'action principale.
- Ensuite : la semaine, puis les objectifs. Pas de mur d'informations.
- Action principale en bas de l'écran ou dans la carte, à portée de pouce.
- Le contenu principal se voit sans zoom ni défilement horizontal.
- Espacements en multiples de 8 pt, réguliers d'un écran à l'autre ; marges latérales 16 à 20 pt.
- Notes repliées par défaut (`Collapsible`) : la première ligne sert d'aperçu.
- Actions secondaires (Adapter, Sans matériel, Échanger des jours) regroupées dans un `Menu`,
  pas une rangée de boutons.
- Prévoir les états : vide (aucun plan), chargement, erreur (import JSON invalide), terminé.
- Dynamic Type testé à la plus grande taille, pas seulement par défaut.
- **iOS 26 / Liquid Glass** : les barres natives (navigation, onglets, outils) prennent le
  nouveau style automatiquement. Les garder natives, sans fond opaque maison, et laisser le
  contenu défiler dessous. L'app vise iOS 17 : toute API Liquid Glass (`glassEffect`…) doit
  être sous `if #available(iOS 26, *)`. Le verre est réservé aux commandes, pas aux cartes.

## Format d'une maquette (avant de coder)

Pour chaque écran :

- **But** : ce que l'utilisateur vient faire ici, en une phrase.
- **Contenu** : les éléments dans l'ordre, de haut en bas, avec leur taille relative.
- **Action principale** : une seule.
- **Actions secondaires** : où elles se trouvent.
- **États** : vide, en cours, erreur, terminé.
- **Petit écran** : ce qui change sur montre 41 mm ou petit iPhone.

## Checklist de relecture

- Comprend-on quoi faire en 2 secondes ?
- Une seule action principale visible ?
- Texte tronqué ou trop petit ? Et avec les grandes tailles de texte ?
- Alignements et espacements cohérents avec les autres écrans ?
- Chaque couleur vient-elle de `Theme` et a-t-elle un sens ?
- Est-ce que ça fait sportif, ou générique ?
- Est-ce que ça ressemble à une app Apple soignée, ou à un prototype ?
- Sur la montre : utilisable en pleine course ?
- Que retirerait-on si on ne pouvait garder que la moitié ?

## Sources

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos) — Apple
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios) — Apple
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) — Apple
- [platform-design-skills](https://github.com/ehmo/platform-design-skills) — skills `ios` et `watchos` (licence MIT)
- [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill) — skill `swiftui-pro` de Paul Hudson (licence MIT)
- [Audits d'accessibilité](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app) — Apple
