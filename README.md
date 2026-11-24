# Coach

App iPhone + Apple Watch de préparation (BueRun, course, escaliers, renfo, martial cross).
Tout reste en local : plan, journaux et données Santé ne quittent pas l'iPhone et la montre.

## Installer sur ton iPhone et ta montre

**Avec TestFlight (recommandé, sans Mac)** : chaque fusion sur `main` envoie une nouvelle version
sur TestFlight (workflow « TestFlight »). Installe l'app TestFlight, puis Coach › « Installer » ;
la montre suit. Il faut un compte Apple Developer payant et la clé App Store Connect dans les
Secrets GitHub (`ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`).

**Avec Xcode (compte gratuit)** :

1. **Xcode › Integrate › Clone…** puis colle `https://github.com/limevolt/coach-app`.
2. Ouvre `Coach.xcodeproj`.
3. Cible **Coach**, puis cible **CoachWatch** : onglet *Signing & Capabilities* › *Team* = ton identifiant Apple.
   Si Xcode signale un identifiant déjà pris, change `com.limevolt` en un nom à toi dans les deux cibles.
4. Branche l'iPhone, schéma **Coach** › ▶︎. Puis schéma **CoachWatch** + ta montre › ▶︎.
5. Mises à jour : double-clique **« Mettre a jour Coach.command »** dans le dossier du projet (Finder).
   Il récupère la dernière version, compile et installe sur l'iPhone et la montre, sans ouvrir Xcode.
   À faire au moins une fois par semaine : avec le compte gratuit, l'app expire après 7 jours.
   Sans câble : iPhone branché une fois, puis Xcode › Window › Devices and Simulators › « Connect via network ».

Mode développeur à activer sur l'iPhone et la montre : Réglages › Confidentialité et sécurité › Mode développeur.

## Comment c'est construit

- `Coach/` : app iPhone (plan, import, suivi, minuteurs, guide des exercices).
- `CoachWatch/` : app montre (renfo guidé, circuits, minuteurs, séance enregistrée dans Santé).
- `Shared/` : modèles du plan, thème, moteur d'animation et bibliothèque d'exercices (les deux apps).
- `project.yml` : description du projet ; `Coach.xcodeproj` est régénéré automatiquement.
- `docs/PLAN_FORMAT.md` : format du plan que l'IA produit (embarqué dans l'app) ; `docs/exemple-plan.json` : plan de test.

La compilation est vérifiée automatiquement sur un Mac de GitHub à chaque mise à jour.
