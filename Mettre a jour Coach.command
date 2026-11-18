#!/bin/bash
# Mettre à jour Coach — double-clique ce fichier dans le Finder.
# 1. récupère la dernière version (branche main)
# 2. compile l'app iPhone + montre avec ton compte Apple (celui connecté dans Xcode)
# 3. l'installe sur ton iPhone et ta montre (câble ou même Wi-Fi)
# À refaire au moins une fois par semaine : avec le compte gratuit, l'app expire après 7 jours.

cd "$(dirname "$0")" || exit 1
set -o pipefail

fail() {
  echo
  echo "❌ $1"
  echo "   Copie ce message à Claude si tu ne sais pas quoi faire."
  read -r -p "Appuie sur Entrée pour fermer…"
  exit 1
}

echo "▶︎ 1/3 Récupération de la dernière version…"
# Une modification locale accidentelle (par Xcode) est mise de côté, pas supprimée.
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "mise de côté avant mise à jour $(date '+%Y-%m-%d %H:%M')" >/dev/null
  echo "  (modifications locales mises de côté : git stash list)"
fi
git checkout -q main || fail "Impossible de passer sur la branche main."
git pull -q --ff-only || fail "Impossible de récupérer la dernière version (connexion ?)."
echo "  Version : $(git log -1 --format='%h — %s')"

# Le projet Xcode doit lister tous les fichiers de code (il est régénéré par GitHub).
MISSING=$(find Coach CoachWatch Shared -name '*.swift' -exec basename {} \; | while read -r f; do
  grep -q "$f" Coach.xcodeproj/project.pbxproj || echo "$f"
done)
[ -z "$MISSING" ] || fail "La nouvelle version est encore en préparation sur GitHub (fichier(s) : $MISSING). Réessaie dans 5 minutes."

echo "▶︎ 2/3 Compilation (1 à 3 minutes)…"
mkdir -p build
rm -rf build/Build/Products
xcodebuild build \
  -project Coach.xcodeproj -scheme Coach -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  > build/compilation.log 2>&1 \
  || { grep -E "error:|Signing|No Account|provisioning" build/compilation.log | sort -u | head -15; fail "La compilation a échoué (journal complet : build/compilation.log)."; }

PHONE_APP="build/Build/Products/Debug-iphoneos/Coach.app"
WATCH_APP="build/Build/Products/Debug-watchos/CoachWatch.app"
[ -d "$PHONE_APP" ] || fail "App iPhone introuvable après la compilation."

echo "▶︎ 3/3 Installation…"
xcrun devicectl list devices --json-output /tmp/coach-devices.json >/dev/null 2>&1 \
  || fail "Impossible de lister tes appareils."

# Appareils appairés : « plateforme udid état nom », les appareils connectés en premier.
DEVICES=$(/usr/bin/python3 - <<'EOF'
import json
d = json.load(open("/tmp/coach-devices.json"))
rows = []
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    conn = dev.get("connectionProperties", {})
    if conn.get("pairingState") != "paired":
        continue
    udid = hw.get("udid") or dev.get("identifier")
    state = conn.get("tunnelState", "?")
    name = dev.get("deviceProperties", {}).get("name", "?").replace(" ", "_")
    rows.append((0 if state == "connected" else 1, hw.get("platform", "?"), udid, state, name))
for r in sorted(rows):
    print(*r[1:])
EOF
)

echo "  Appareils trouvés :"
echo "$DEVICES" | awk '{printf "   - %s (%s, %s)\n", $4, $1, $3}'

# Essaie chaque appareil d'une plateforme jusqu'à ce que l'installation réussisse.
install_on() { # $1 = plateforme, $2 = app
  local udid ok=1
  for udid in $(echo "$DEVICES" | awk -v p="$1" '$1==p{print $2}'); do
    if xcrun devicectl device install app --device "$udid" "$2" >/tmp/coach-install.log 2>&1; then
      ok=0; break
    fi
  done
  return $ok
}

echo "$DEVICES" | grep -q '^iOS ' || fail "Aucun iPhone appairé. Branche-le au Mac avec le câble et réessaie."

install_on iOS "$PHONE_APP" \
  || { tail -5 /tmp/coach-install.log; fail "Installation sur l'iPhone impossible. Branche-le avec le câble (déverrouillé), ou active Xcode › Window › Devices and Simulators › « Connect via network »."; }
echo "  ✅ iPhone à jour"

if [ -d "$WATCH_APP" ] && echo "$DEVICES" | grep -q '^watchOS ' && install_on watchOS "$WATCH_APP"; then
  echo "  ✅ Montre à jour"
else
  echo "  ⚠️  Montre non mise à jour directement : elle se met souvent à jour seule via l'iPhone"
  echo "     en quelques minutes (montre au poignet, déverrouillée). Sinon : Xcode › schéma CoachWatch › ▶︎"
fi

echo
echo "🎉 Terminé."
read -r -p "Appuie sur Entrée pour fermer…"
