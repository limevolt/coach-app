# WORKFLOW.md — app Coach

> Façon de travailler, commune à toutes les conversations Claude (écrites ou vocales).
> Ce fichier est aussi dans les fichiers du projet Claude « Coach – développement ».
> Toute nouvelle décision sur la méthode est notée ici, dans les deux copies.
>
> Chaque section est marquée **[générique]** (réutilisable telle quelle pour une autre app)
> ou **[Coach]** (propre à cette app). Objectif : en faire un jour un modèle pour de nouvelles
> apps (voir l'issue « Exporter le workflow en modèle réutilisable »).

## Qui fait quoi [générique]

- **Le propriétaire de l'app** teste l'app pendant ses séances, donne ses retours et valide les maquettes. Il ne relit pas le code.
- **Claude en conversation écrite** a accès au dépôt. Il crée les issues, code, ouvre les pull requests et les fusionne lui-même (choix du propriétaire, 25/11/2026).
- **Claude en vocal** n'a pas toujours accès à GitHub. Il recueille les retours, les classe et prépare un texte à coller dans une conversation écrite.
- Il n'y a pas d'autre outil : tout passe par les conversations Claude du projet.

## Règle n° 1 : les GitHub Issues sont la seule source [générique]

- Tout bug, toute idée et toute décision vit dans une issue, pas dans un document à part.
- Avant de créer une issue, chercher si elle existe déjà. Si oui, ajouter un commentaire avec ce qui est nouveau.
- Étiquettes : `bug` ou `enhancement`, plus `iPhone`, `Montre` ou `Design`. Ajouter `priorité haute` quand un problème empêche de faire une séance, `en cours` quand le travail a commencé, et `à retester` quand un bug est peut-être déjà corrigé.
- `obsolète` : issue déjà corrigée, remplacée par une autre ou en double. Claude ajoute l'étiquette et un commentaire court (pourquoi, avec le lien vers la PR ou l'issue qui la remplace), sans fermer l'issue : c'est le propriétaire qui la ferme.
- Une issue de bug dit toujours : ce qui s'est passé, ce qui était attendu, et comment le reproduire. Sans données personnelles (voir `CLAUDE.md`).

## Tableau de bord [générique]

Deux endroits, chacun mis à jour sans effort manuel.

### Tickets : le tableau GitHub « Coach App »

- Tableau GitHub Projects (privé) relié au dépôt. Colonnes : **À faire**, **En cours**, **À tester par moi**, **À fusionner**, **Fait**.
- Les cartes se rangent toutes seules grâce à l'action `.github/workflows/tableau.yml` (script `.github/scripts/tableau.js`, jeton `PROJECT_TOKEN` dans les secrets du dépôt), d'après l'état et les étiquettes, la première règle qui s'applique gagnant :
  1. pull request ouverte → À fusionner (brouillon → En cours) ; fermée ou fusionnée → Fait ;
  2. issue fermée ou `obsolète` → Fait (le propriétaire ferme les `obsolète`) ;
  3. `à retester` → À tester par moi ;
  4. `en cours`, ou une PR ouverte qui la ferme → En cours ;
  5. sinon → À faire.
- Les conversations Claude n'ont pas accès au tableau lui-même (permission séparée du dépôt) : pour déplacer une carte, Claude change l'étiquette. Une carte déplacée à la main peut revenir à sa place au prochain changement de son issue.
- Lancement manuel (onglet Actions → « Tableau GitHub » → Run workflow) : range tout le tableau d'un coup.
- Automatismes intégrés du tableau (menu Workflows) : garder « Auto-add to project », « Item closed », « Item reopened », « Pull request linked to issue », « Pull request merged » ; éteindre « Item added to project » et « Auto-close issue ».
- Le détail reste dans chaque issue : ce que le propriétaire doit faire y est écrit en commentaire.

### Conversations : la page « Coach · tableau de bord »

- Page claude.ai privée au propriétaire : https://claude.ai/artifact/P8tSx7QD6HQc5EeKWXzr2D, onglet « Conversations ». Une ligne par conversation du projet, « Attend ta réponse » ou « Terminée », avec « À toi » (ce que le propriétaire doit répondre ou faire) et « Fait » (ce qu'elle a produit).
- Données dans le bloc `<script id="data">` de la page, liste `convs` : `u` (lien), `t` (titre), `d` (date AAAA-MM-JJ), `st` (`wait` ou `done`), `toi`, `fait`. Modifier ces lignes avec l'outil d'artefact (`edit_version`, après lecture de la version), sans toucher au reste de la page.
- **Mise à jour automatique** : une tâche programmée (« Tableau de bord : conversations ») repasse chaque soir à 20 h 57 sur les conversations du jour et met la liste à jour.
- En plus, chaque conversation met sa propre ligne à jour avant de finir quand elle le peut. `wait` si elle se termine sur une question ou une validation attendue (maquette, PR à fusionner, essai), `done` sinon. Quand elle règle ce qu'une autre conversation attendait, elle passe aussi la ligne de l'autre en `done`.
- L'onglet « Tickets » de la page est retiré une fois le tableau GitHub en place.
- Même règle de vie privée que partout : décrire l'app, jamais la vie du propriétaire.

## Après chaque séance : le retour [générique]

(Pour une autre app : « séance » = « utilisation réelle de l'app ».)

1. Le propriétaire raconte son test, à l'écrit ou en vocal.
2. Claude résume chaque point en une phrase et le relie à une issue existante ou nouvelle.
3. Sans accès au dépôt, Claude donne à la fin un texte prêt à coller dans une conversation écrite.
4. Avec accès, Claude crée ou commente directement les issues, puis donne leur liste.

## Cycle de développement [générique]

1. **Choisir un lot** : quelques issues liées, en commençant par `priorité haute`. Leur mettre l'étiquette `en cours`.
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
7. **Fusion sur `main` par Claude**, sans attendre le propriétaire (choix du 25/11/2026 : il ne relit pas le code), dès que la compilation est verte et que les remarques bloquantes des relectures sont corrigées. Seule exception : un écran dont la maquette n'a pas été validée, ou un doute sur la vie privée → on attend le propriétaire. Les issues passent en `à retester` (retirer `en cours`).
8. **Prévenir le propriétaire** quand la version est sur TestFlight (workflow « TestFlight », #89) : la version est prête, quoi tester, et sur quelle issue répondre.

## Économiser les compilations [générique]

- Regrouper les correctifs : une compilation par lot, pas une par correction.
- `[skip ci]` pour les changements qui ne touchent que la doc ou les règles.
- `[captures]` seulement quand l'interface change, une fois le code prêt.
- Ne pas pousser pendant que des captures tournent.
- Le dépôt est public depuis le 18/11/2026 : les compilations sont gratuites, mais restent longues. Grouper reste la règle. (L'action du tableau est un petit travail de quelques secondes, sans compilation.)

## Avant le sport : vérification en deux minutes [Coach]

1. Installer la dernière version : app TestFlight › Coach › « Mettre à jour » (la montre suit).
2. Sur l'iPhone, ouvrir la semaine, choisir la séance du jour et appuyer sur « Démarrer ».
3. Sur la montre, vérifier que la séance arrive prête et ne démarre qu'après un seul « Commencer ».
4. Si ça bloque, noter ce qu'on voit (photo de l'écran si possible) pour le retour d'après séance.

## Début et fin de conversation [générique]

- **Au début** : relire `WORKFLOW.md`, `CLAUDE.md` et `DESIGN.md`, regarder les issues ouvertes `priorité haute` et l'onglet Conversations, et rappeler en une phrase où on en est.
- **À la fin** : mettre à jour les issues touchées et leurs étiquettes (le tableau GitHub suit), puis la ligne de cette conversation dans l'onglet Conversations, et noter ici toute nouvelle décision sur la façon de travailler.

## En attente [générique]

- Tableau GitHub : action fusionnée (#103) et étiquette `en cours` créée. Reste au propriétaire : vérifier le secret `PROJECT_TOKEN`, lancer le premier rangement (onglet Actions → « Tableau GitHub » → Run workflow), puis retirer l'onglet Tickets de la page.
- Exporter ce workflow en modèle réutilisable (dépôt modèle + skill « nouvelle app »), une fois la méthode stable.
