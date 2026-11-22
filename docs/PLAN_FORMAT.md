# Format du plan — app Coach (schemaVersion 1)

> L'app ajoute déjà ce texte (à partir de « Consigne pour l'IA ») à la demande de nouveau plan et au suivi.
> Ce fichier est embarqué dans l'app : le modifier change aussi ce que l'app envoie à l'IA.

## Consigne pour l'IA

Tu es mon coach course + renforcement musculaire. Tu produis mon plan au format JSON ci-dessous, dans un seul bloc de code. Mets des consignes pas à pas (`instructions`) pour chaque exercice, en commençant par des exercices classiques. Quand je t'envoie un suivi (généré par l'app), tu l'analyses (séances faites ou manquées, effort perçu, FC, allures, charges, circuits, séances libres, FC au repos, VFC, progression vers les objectifs) et tu renvoies le plan complet mis à jour : même `planId`, `version` + 1, séances datées à partir d'aujourd'hui, objectifs mis à jour (`current`, `progress`). Construis le plan à rebours depuis l'échéance des objectifs, avec une semaine allégée toutes les 3 ou 4 semaines. Pour chaque exercice avec charge ou matériel, ajoute une variante `noEquipment` (au poids du corps). Si le suivi ou la demande indique « Jours disponibles pour m'entraîner », place les séances **uniquement ces jours-là**.

**Textes courts** : `notes` (plan et séances) = 3 à 5 lignes maximum, une idée par ligne, commençant par `- `. Pas de paragraphe. `**gras**` autorisé pour l'essentiel (allure, zone, consigne clé). La première ligne doit résumer la séance : elle sert d'aperçu quand le texte est replié.

## Structure

Champs **obligatoires** du plan : `schemaVersion` (toujours 1), `planId`, `version`, `title`, `sessions` (au moins une séance). Un plan sans l'un d'eux est refusé à l'import.

```json
{
  "schemaVersion": 1,
  "planId": "texte stable, ex. 10k-printemps-2027",
  "version": 1,
  "title": "Titre court",
  "notes": "Consignes générales (facultatif)",
  "goals": [ ...objectifs (facultatif)... ],
  "sessions": [ ...séances... ]
}
```

### Objectif

```json
{ "id": "g1", "title": "10 km en moins de 60 min", "date": "2027-03-14",
  "baseline": "10 km en 66 min", "current": "estimé 63 min", "target": "< 60:00", "progress": 0.4 }
```
Seuls `id`, `title` et `date` sont obligatoires. `progress` va de 0 à 1.

### Séance

| Champ | Obligatoire | Valeurs |
|---|---|---|
| `id` | oui | unique dans le plan, ex. `s1-run1` |
| `date` | oui | `AAAA-MM-JJ` |
| `time` | non | `HH:mm` (07:00 par défaut) |
| `type` | oui | `run`, `strength` ou `circuit` |
| `title` | oui | texte court (affiché sur la montre) |
| `notes` | non | 3 à 5 lignes courtes commençant par `- ` (la 1re = résumé) |
| `equipment` | non | `none` = séance prévue à la maison, sans matériel (l'app applique les variantes `noEquipment`) |
| `run` / `strength` / `circuit` | selon `type` | voir ci-dessous |

### Course (`run`) → app Exercice de la montre (WorkoutKit)

```json
"run": {
  "location": "outdoor",
  "warmup":  { "goal": {...}, "alert": {...} },
  "blocks": [
    { "iterations": 6, "steps": [
      { "purpose": "work",     "goal": {...}, "alert": {...} },
      { "purpose": "recovery", "goal": {...} }
    ]}
  ],
  "cooldown": { "goal": {...} }
}
```

- `location` : `outdoor` (défaut) ou `indoor` (tapis).
- `goal` : `{ "type": "time", "value": 10, "unit": "min" | "s" }`, `{ "type": "distance", "value": 400, "unit": "m" | "km" }` ou `{ "type": "open" }`.
- `alert` (facultatif) : `{ "type": "hrZone", "zone": 1-5 }` ou `{ "type": "pace", "min": "4:50", "max": "5:10" }` (min/km ; `min` = l'allure la plus rapide).
- Un footing continu = un bloc avec `iterations: 1` et une seule étape `work`.
- Tabata en course : bloc `iterations: 8`, étapes `work` 20 s + `recovery` 10 s.

### Renfo séries/répétitions (`strength`) → app Coach sur la montre

```json
"strength": { "exercises": [
  { "name": "Squat", "sets": 4, "reps": 8, "weightKg": 20, "restSec": 90,
    "notes": "...", "instructions": ["étape 1", "étape 2"], "videoURL": "https://..." },
  { "name": "Gainage", "sets": 3, "durationSec": 45, "restSec": 45 }
]}
```

- `reps` OU `durationSec` (exercice chronométré).
- `weightKg` facultatif (le réglage +/- du poids n'apparaît que s'il est présent, même à 0).
- `restSec` : repos après chaque série (60 s par défaut).

### Circuit / Tabata enchaîné (`circuit`) → app Coach sur la montre

Tout s'enchaîne automatiquement : effort → repos → exercice suivant → … → récup entre les tours.

```json
"circuit": {
  "rounds": 8, "workSec": 20, "restSec": 10, "roundRestSec": 10, "prepareSec": 10,
  "exercises": [
    { "name": "Squat sauté", "instructions": ["..."] },
    { "name": "Pompes", "durationSec": 30 }
  ]
}
```

- `durationSec` sur un exercice remplace `workSec` pour cet exercice.
- `roundRestSec` : repos entre deux tours (sinon `restSec`). `prepareSec` : compte à rebours de départ (5 s par défaut, 5 s minimum ; le chrono de la séance part à sa fin).
- Tabata classique = 1 exercice, `rounds` 8, `workSec` 20, `restSec` 10.

### Variante sans matériel (`noEquipment`)

Pour chaque exercice avec charge ou matériel (haltères, barre, machine…), ajoute une variante au poids du corps. Elle est utilisée quand je choisis « Sans matériel » dans l'app (bouton « Adapter ») ou quand la séance a `"equipment": "none"`.

```json
{ "name": "Rowing haltères", "sets": 3, "reps": 10, "weightKg": 12, "restSec": 75, "animation": "row",
  "noEquipment": { "name": "Rowing sac à dos", "reps": 12, "animation": "row",
                   "instructions": ["Remplis un sac à dos.", "Buste penché, dos plat.", "Tire le sac vers le nombril."] } }
```

- Champs : `name` (obligatoire), `sets`, `reps` ou `durationSec`, `restSec`, `notes`, `instructions`, `animation`. Les champs absents reprennent ceux de l'exercice.
- Sans `noEquipment`, l'app choisit une variante intégrée (squat → squat sauté, rowing → rowing sac à dos, mollets → mollets sur une marche…) ou retire la charge.

### Champs remplis par l'app

L'utilisateur peut adapter une séance depuis l'iPhone (autre activité, sans matériel, échange de jours). L'app note alors dans la séance :
- `originalDate` : date prévue à l'origine (séance déplacée) ;
- `replaces` : titre de la séance remplacée ;
- `coachNote` : ce que le coach de l'app a changé (« Déplacée par le coach (squash jeudi) », « Allégée par le coach (squash la veille) »).

Le suivi les signale. Dans le plan mis à jour, **supprime `originalDate`, `replaces` et `coachNote`** (tiens-en compte pour la suite).

### Consignes et vidéos (tous les exercices)

- `instructions` : liste de 2 à 5 phrases courtes (position, mouvement, erreurs à éviter). Affichées sur la montre (« Comment faire ? ») et sur l'iPhone.
- `mistakes` : erreurs à éviter (facultatif ; sinon celles de la bibliothèque).
- `animation` : animation intégrée à utiliser. Valeurs : `squat`, `squatJump`, `pushup`, `plank`, `sidePlank`, `lunge`, `jumpingJack`, `mountainClimber`, `rdl` (soulevé de terre roumain), `row` (rowing haltères), `calfRaise` (mollets), `gluteBridge` (pont fessier). Si absent, l'app la devine d'après le nom (« Squat sauté », « Pompes », « Fentes »…). Privilégie ces exercices : ils sont animés. Pour un autre exercice, mets des `instructions` détaillées.
- `videoURL` : lien vers une démo (YouTube, fichier iCloud, vidéo générée par IA…). Bouton « Voir la démo » sur l'iPhone.

## Limites

- La montre garde au maximum 15 séances de course programmées. L'app reprogramme les suivantes à l'ouverture (une fois par jour).
- Les séances de course passées ne sont pas reprogrammées.
