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
   du propriétaire… mais seulement après l'étape suivante.
   - **Critique de la maquette (avant le propriétaire).** Lancer l'agent `design-reviewer` en
     mode « maquette » : il raisonne comme un designer Apple expérimenté (skills iOS/watchOS,
     ce fichier, checklist de relecture) et rend une liste courte de remarques classées.
     Corriger la maquette, puis la présenter au propriétaire avec les remarques non retenues.
     C'est ici que la relecture design rapporte le plus : corriger un dessin ne coûte rien.
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
4. **Contrôle de conformité.** Lancer l'agent `design-reviewer` en mode « conformité » sur les
   captures : il vérifie seulement que le rendu réel correspond à la maquette validée et qu'il
   tient (texte coupé, très grand texte, petits écrans, contraste réel), sans refaire de
   critique du design. Corriger les écarts, puis refaire les captures si le rendu a changé.
   En parallèle, l'agent `code-reviewer` relit la logique du code.
5. **Pull request avec images.** Lister les écrans touchés et joindre les captures clés
   (liens vers `ci-captures`), avec les écarts restants assumés. Le propriétaire valide sur les images.
6. **Retour d'usage.** Chaque remarque du propriétaire après un test sur son iPhone ou sa montre
   devient une règle dans ce fichier, pour ne pas refaire la même erreur.
7. Si un choix va contre ce fichier, le dire et le justifier.

## Identité visuelle : « nouvelle ambiance » (validée le 20/11/2026, #40)

Direction : **sportif, mais calme**. Inspirée des apps de suivi de données : un gros chiffre qui
se lit en une seconde, quelques petits chiffres, presque plus de bordures. Référence visuelle :
le canevas « Coach — nouvelle ambiance ». Valeurs dans `Shared/Theme.swift`.

### Un seul héros par écran
- Un seul élément gros sur l'écran : le **héros** (76 pt, semi-gras, `Font.hero`). Tout le reste
  est plus petit et plus discret.
- **Dégradé citron vert → turquoise (`Theme.heroGradient`) réservé à la progression** : accueil
  (séances faites de la semaine) et Suivi. Sur une séance, le héros (la durée) est en blanc.

### Couleurs
- Fond presque noir `Theme.bg` #06080B.
- **Une seule carte pleine** par écran (`Theme.card` #11151B, rayon 24, **sans bordure**) : l'action
  du moment. Le reste en **lignes simples** séparées par `Theme.separator`, avec un chevron `Theme.chevron`.
- `Theme.card2` #1A2029 : tuile dans une carte, bouton sélectionné. `Theme.line` #2A313C : contour
  d'un bouton discret, tiret d'un jour de repos.
- Texte : `Theme.text` pour l'essentiel, `Theme.muted` pour le secondaire et les petits titres.
- Accents, chacun avec **un sens fixe**, utilisés **pour les données** (pastilles, barres, points,
  étiquette du type de séance) plutôt que pour la décoration :
  - citron vert `Theme.accent` #C6F432 : action principale, aujourd'hui, progression, circuits ;
  - turquoise `Theme.teal` #2DD4BF : renforcement ;
  - orange `Theme.warm` #FF7A45 : course, intensité.
- Texte sur fond citron vert : `Theme.accentDark`. Icône sur une pastille pleine : `Theme.onTint`.

### Typographie : 5 tailles, pas une de plus
Police **Outfit** partout, via `Font.coach(...)` (`Shared/Typography.swift`). Le très gras disparaît.

| Rôle | Taille | Graisse | Dans le code |
|---|---|---|---|
| Héros | 76 (montre : 44) | semi-gras | `Font.hero` |
| Titre d'écran | 30 | semi-gras | `Font.screenTitle` |
| Chiffre, titre de carte | 22 | semi-gras | `Font.number` (+ unité grise `Font.unit`) |
| Texte | 17 | moyen | `Font.text` |
| Étiquette | 12, capitales, gris | semi-gras | `Eyebrow` (`Font.label`) |

Le texte secondaire gris sous un titre utilise `Font.detail` (15, normal). Boutons : 17 gras.
Toutes ces tailles suivent Dynamic Type, sauf le héros (taille fixe, comme les chronos de la montre).

### Formes et espaces
- Marges latérales 20 (`Theme.screenMargin`), 24 à 28 entre les blocs (`Theme.blockSpacing`).
- Bouton principal : plein citron vert, 52 de haut, rayon 16 (`primaryActionStyle`).
- Bouton discret : contour gris, texte blanc, 44 de haut (`quietActionStyle`).
- Lignes de liste : 52 de haut (`Theme.rowHeight`).

### Règles du thème
- Jamais de couleur en dur dans une vue : l'ajouter à `Theme` si elle manque.
- Sur un même écran : un accent dominant, deux au maximum (hors couleurs des types de séance
  dans les données).
- La couleur s'accompagne toujours d'une icône (`Theme.icon(for:)`) ou d'un mot.
- Tailles de texte via l'échelle ci-dessus. Jamais de `.system(...)` pour du texte (les icônes
  SF Symbols, si). Seuls le héros et les très grands chiffres de la montre (40 pt et plus) ont
  une taille fixe. `Font.display` (ancien style très gras) disparaît au fil de la migration.
- Vérifier le contraste de chaque couleur de texte sur son fond (4,5:1 minimum).
- Icônes : SF Symbols, même graisse sur un écran.
- Pas de graphique hors du Suivi.

### Montre
La montre garde ses tailles de chronos (`Theme.watch…`) jusqu'à son lot : même ambiance, un
chiffre géant ; pendant l'effort, fond teinté et chiffre de la couleur du type ; pendant le
repos et « Prêt ? », chiffre blanc sur fond carte.

### Encore ouvert
- Sombre uniquement, ou aussi un mode clair ?

## Principes généraux

- Une information principale par écran. Le reste est secondaire et plus discret.
- Composants natifs SwiftUI d'abord (comportement et accessibilité), habillés avec `Theme`.
- Trois niveaux de texte maximum par écran.
- Cibles tactiles d'au moins 44 pt, contraste suffisant, libellés VoiceOver sur les icônes.
- **Une icône a la couleur de son texte.** Une action destructive (rouge) a son icône rouge aussi,
  y compris dans les menus (`DestructiveButton`).
- **Chaque appui a un retour visible** : état de chargement dans le bouton pendant une attente,
  sans que la mise en page saute.

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
- **Un seul « Commencer » par séance.** Avant le départ, c'est le seul bouton visible. Il lance un
  compte à rebours « Prêt ? » de 5 s (chiffre géant, exercice qui arrive, 3 vibrations à la fin),
  puis le chrono et le premier exercice partent ensemble et tout s'enchaîne. Le chrono ne tourne
  pas avant la fin du compte à rebours. Même chose quand la séance est lancée depuis l'iPhone.
- **Couleur plein écran** (teinte du type de séance) pour signaler l'état d'un coup d'œil :
  effort, repos, terminé.
- Retour haptique aux transitions (début, fin de série, fin de repos).
- Vérifier l'affichage permanent (luminosité réduite, `isLuminanceReduced`).
- **Pas d'explications sur la montre** (pas de « Comment faire ? ») : elles restent sur l'iPhone.
- **Commandes sur une page à part** (pause, passer, +30 s, terminer, FC, durée) : on y arrive en
  glissant vers la droite, comme dans l'app Exercice. Les écrans d'effort et de repos n'ont pas
  d'autre bouton que l'action de l'étape (« Série faite »).
- **Lancer depuis l'iPhone** : « Démarrer » (un seul gros bouton, sans texte autour ; même libellé sur l'accueil et sur la séance)
  ouvre Coach sur la montre et la séance y démarre aussitôt, sans second « Commencer » (choix du
  propriétaire, 18/11/2026). Exception : une course s'ouvre prête, l'app Exercice demande son départ.
- Doit rester utilisable en courant, en sueur, avec des doigts mouillés.

## iPhone

- **Accueil (version pastilles, #40)** : de haut en bas, « Semaine x sur y · dates » et le titre
  « Cette semaine » avec le bouton ••• ; le héros « séances faites / prévues » ; la semaine en
  **7 pastilles** (pleine = faite, contour = prévue, tiret = repos, anneau citron vert = aujourd'hui,
  icône du type dans la pastille ; toucher une pastille ouvre la séance) ; **la carte du jour**,
  qui change selon le jour (à faire → « Démarrer » ; faite → ses chiffres et « Voir le détail » ;
  repos → la prochaine séance et « Séance libre ») ; puis « À venir » en lignes simples. Objectifs,
  consignes et autres semaines viennent ensuite, repliés. Pas de graphique sur l'accueil.
- **Titres d'écran courts, sur une seule ligne** même sur un iPhone de 375 pt (« Ton objectif »,
  pas « Quel est ton objectif ? ») : la question va dans le texte gris dessous (retour du propriétaire, #45).
- **Choix en onglets : composant `SegmentedChoice`**, jamais le `Picker` segmenté natif (style par défaut
  d'Apple, pas celui de Coach) : cadre gris fin, option choisie sur fond `Theme.card2` en blanc (retour du
  propriétaire, #45).
- **Jours de la semaine en 2 lettres** (Lu, Ma, Me…) dans les grilles de 7 : pas de coche ni d'abréviation
  de 3 lettres, qui ne tiennent pas. Jour choisi = fond `Theme.card2`, contour citron vert, texte gras (#45).
- **Interrupteurs : style `.toggleStyle(.coach)`** (`Coach/CoachControls.swift`), jamais le `Toggle` natif
  vert : capsule `Theme.card2`, contour gris (`Theme.controlStroke`) à l'arrêt, contour et pastille citron
  vert avec une coche quand c'est activé — l'état se lit sans la couleur (option A, retour du propriétaire, #45).
- **Plusieurs choix possibles : case à cocher `CoachCheckbox`** (carré arrondi, coche citron vert), pas un
  rond (le rond = choix unique, `RadioRow`). Exemple : les disciplines de l'assistant.
- **Séances d'une autre app (#54)** : activité en plus = pastille `Theme.extraFill` + contour `Theme.muted` + icône
  du sport (`ActivityCatalog`, SF Symbol `figure.*`, silhouette générique sinon) ; ligne `ExtraActivityLine` toute
  en gris. Autre sport choisi comme « Séance principale du jour » = pastille pleine comme une séance faite, avec
  l'icône du sport. Ressenti : `EffortPicker` (5 gros boutons, 2 Facile → 10 Max) partout.
- **Niveaux (intensité du plan, #57)** : `RadioRow` avec `bars` (barres 1 à 4 `IntensityBars`, couleur du texte
  et gris, jamais citron vert : il reste pour le choix et « Continuer »), `tag` (« Conseillé », étiquette au
  contour gris) et `note` (garde-fou sous le choix, icône grise). En très grand texte, les barres passent
  sous le titre.
- **Accordéon** : les options d'une ligne cochée (pastilles de variantes, jour et heure du cours) se déplient
  sous la ligne (fondu + glissement vers le bas) et se replient quand on décoche ; simple fondu si
  « Réduire les animations » est activé.
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
