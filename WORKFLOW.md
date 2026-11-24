# WORKFLOW.md — app Coach

> Façon de travailler, commune à toutes les conversations Claude (écrites ou vocales).
> Ce fichier est aussi dans les fichiers du projet Claude « Coach – développement ».
> Toute nouvelle décision sur la méthode est notée ici, dans les deux copies.
>
> Chaque section est marquée **[générique]** (réutilisable telle quelle pour une autre app)
> ou **[Coach]** (propre à cette app). Objectif : en faire un jour un modèle pour de nouvelles
> apps (voir l'issue « Exporter le workflow en modèle réutilisable »).

## Qui fait quoi [générique]

- **Le propriétaire de l'app** teste l'app pendant ses séances, donne ses retours et valide les maquettes et les pull requests.
- **Claude en conversation écrite** a accès au dépôt. Il crée les issues, code, ouvre et fusionne les pull requests.
- **Claude en vocal** n'a pas toujours accès à GitHub. Il recueille les retours, les classe et prépare un texte à coller dans une conversation écrite.
- Il n'y a pas d'autre outil : tout passe par les conversations Claude du projet.

## Règle n° 1 : les GitHub Issues sont la seule source [générique]

- Tout bug, toute idée et toute décision vit dans une issue, pas dans un document à part.
- Avant de créer une issue, chercher si elle existe déjà. Si oui, ajouter un commentaire avec ce qui est nouveau.
- Étiquettes : `bug` ou `enhancement`, plus `iPhone`, `Montre` ou `Design`. Ajouter `priorité haute` quand un problème empêche de faire une séance, et `à retester` quand un bug est peut-être déjà corrigé.
- `obsolète` : issue déjà corrigée, remplacée par une autre ou en double. Claude ajoute l'étiquette et un commentaire court (pourquoi, avec le lien vers la PR ou l'issue qui la remplace), sans fermer l'issue : c'est le propriétaire qui la ferme.
- Une issue de bug dit toujours : ce qui s'est passé, ce qui était attendu, et comment le reproduire. Sans données personnelles (voir `CLAUDE.md`).

## Tableau de bord : la page « Coach · tableau de bord » [générique]

- Une page claude.ai, privée au propriétaire, montre où en est l'app d'un coup d'œil, sur téléphone : https://claude.ai/artifact/P8tSx7QD6HQc5EeKWXzr2D. Elle résume les issues sans les remplacer : le détail reste dans chaque issue.
- En haut, un compteur par colonne, avec un point par carte (citron vert : quelque chose attend le propriétaire ; contour orange : `priorité haute`). En dessous, cinq colonnes : **À faire**, **En cours**, **À tester par moi**, **À fusionner**, **Fait** (issues `obsolète` que le propriétaire doit fermer). Chaque issue ouverte et chaque pull request ouverte y a une carte, et une seule.
- Chaque carte : numéro, titre court, puis « À toi » (ce que le propriétaire doit faire, ou « Rien. ») et « Fait » (ce qui a été fait). Phrases courtes, sans jargon.
- **Chaque conversation met à jour les cartes touchées avant de finir** : déplacer, ajouter, retirer une carte fermée, réécrire les deux lignes, changer la date `maj`. Les données sont dans le bloc `<script id="data">` de la page, une carte par ligne (`n`, `col` = todo / doing / test / merge / done, `t`, `toi`, `fait`, et au besoin `pr`, `kind` = bug / idee / a11y, `on`, `haute`, `later`). Modifier ces lignes avec l'outil d'artefact (`edit_version`, après `get_artifact` pour la version), sans toucher au reste de la page.
- **Vue « Conversations »** (deuxième onglet de la page) : une ligne par conversation du projet, « Attend ta réponse » ou « Terminée », avec « À toi » (ce que le propriétaire doit répondre ou faire) et « Fait » (ce qu'elle a produit). Données dans le même bloc, liste `convs` : `u` (lien de la conversation), `t` (titre), `d` (date AAAA-MM-JJ), `st` (`wait` ou `done`), `toi`, `fait`.
- **Chaque conversation met aussi sa propre ligne à jour avant de finir** (l'ajoute si elle n'y est pas). `wait` si elle se termine sur une question ou une validation attendue (maquette, PR à fusionner, essai), `done` sinon. Quand elle règle ce qu'une autre conversation attendait, elle passe aussi la ligne de l'autre en `done`.
- Sans accès aux artefacts (conversation vocale, par exemple) : donner à la fin les cartes et la ligne de conversation à changer, à coller dans une conversation écrite.
- Même règle de vie privée que partout : décrire l'app, jamais la vie du propriétaire.
- Pourquoi pas GitHub Projects : les conversations Claude n'ont accès qu'au dépôt, pas aux tableaux Projects ; elles ne pourraient pas le tenir à jour.

## Après chaque séance : le retour [générique]

(Pour une autre app : « séance » = « utilisation réelle de l'app ».)

1. Le propriétaire raconte son test, à l'écrit ou en vocal.
2. Claude résume chaque point en une phrase et le relie à une issue existante ou nouvelle.
3. Sans accès au dépôt, Claude donne à la fin un texte prêt à coller dans une conversation écrite.
4. Avec accès, Claude crée ou commente directement les issues, puis donne leur liste.

## Cycle de développement [générique]

1. **Choisir un lot** : quelques issues liées, en commençant par `priorité haute`.
2. **Pour un écran** : maquette en amont du code (détail dans `DESIGN.md`) :
   1. Claude propose une maquette selon `DESIGN.md` ;
   2. l'agent `design-reviewer` la critique (mode « maquette ») comme un designer Apple expérimenté ;
   3. Claude corrige la maquette, puis la montre au propriétaire avec les remarques restantes ;
   4. le propriétaire valide. On ne code rien avant.
3. **Coder sur une branche**, en suivant `CLAUDE.md` (vie privée, conventions, composants partagés). Jamais de push direct sur `main`.
4. **Un test automatique pour chaque bug corrigé**, pour qu'il ne revienne pas.
5. **Relecture par des agents indépendants**, qui n'ont pas écrit le code :
   - `code-reviewer` : logique, cas limites, régressions, tests, respect de `CLAUDE.md`, cohérence iPhone ↔ montre ;
   - `design-reviewer` (mode « conformité ») : vérifie seulement que les captures correspondent à la maquette validée et que le rendu réel tient (texte coupé, grand texte, petits écrans, contraste). Pas de nouvelle critique du design.
   - `coach-reviewer` [Coach], dès qu'un lot touche le moteur de coaching (`Coach/Engine/`) : relit les décisions d'entraînement comme un entraîneur (sécurité, règles décidées, sportifs fictifs) et propose des règles pour améliorer le coach.
6. **Pull request** : ce qui change, les issues fermées, le résultat des relectures et ce que le propriétaire doit tester.
7. **Fusion sur `main`** : la version part sur TestFlight (workflow « TestFlight », #89), et les issues sont fermées ou passées en `à retester`.

## Économiser les compilations [générique]

- Regrouper les correctifs : une compilation par lot, pas une par correction.
- `[skip ci]` pour les changements qui ne touchent que la doc ou les règles (sauf `docs/PLAN_FORMAT.md`, embarqué dans l'app).
- `[captures]` seulement quand l'interface change, une fois le code prêt.
- Ne pas pousser pendant que des captures tournent.
- Le dépôt est public depuis le 18/11/2026 : les compilations sont gratuites, mais restent longues. Grouper reste la règle.

## Avant le sport : vérification en deux minutes [Coach]

1. Installer la dernière version : app TestFlight › Coach › « Mettre à jour » (la montre suit).
2. Sur l'iPhone, ouvrir la semaine, choisir la séance du jour et appuyer sur « Démarrer ».
3. Sur la montre, vérifier que la séance arrive prête et ne démarre qu'après un seul « Commencer ».
4. Si ça bloque, noter ce qu'on voit (photo de l'écran si possible) pour le retour d'après séance.

## Début et fin de conversation [générique]

- **Au début** : relire `WORKFLOW.md`, `CLAUDE.md` et `DESIGN.md`, regarder le tableau de bord et les issues ouvertes `priorité haute`, et rappeler en une phrase où on en est.
- **À la fin** : mettre à jour les issues touchées, **puis leurs cartes et la ligne de cette conversation dans le tableau de bord**, et noter ici toute nouvelle décision sur la façon de travailler.

## En attente [générique]

- Exporter ce workflow en modèle réutilisable (dépôt modèle + skill « nouvelle app »), une fois la méthode stable.
