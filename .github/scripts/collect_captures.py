#!/usr/bin/env python3
"""Rassemble les captures des tests d'interface dans un dossier lisible sur GitHub.

Usage : collect_captures.py <dossier de sortie> <dossier>=<fichier.xcresult>=<nom de l'appareil> ...
Pour chaque résultat : exporte les pièces jointes (captures PNG, rapport d'audit, notes),
les renomme proprement, puis écrit un README.md qui montre tout sur une seule page.
"""
import json
import os
import re
import shutil
import subprocess
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.[A-Za-z0-9]+$)")

sections = []
audits = []
notes = []

for spec in sys.argv[2:]:
    folder, bundle, device = spec.split("=", 2)
    if not os.path.isdir(bundle):
        sections.append(f"## {device}\n\nPas de résultat : les tests n'ont pas tourné sur cet appareil.\n")
        continue
    raw = os.path.join(out, "_raw", folder)
    os.makedirs(raw, exist_ok=True)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle,
                    "--output-path", raw], check=False)
    manifest_path = os.path.join(raw, "manifest.json")
    entries = json.load(open(manifest_path)) if os.path.exists(manifest_path) else []
    target = os.path.join(out, folder)
    os.makedirs(target, exist_ok=True)

    images = []
    for entry in entries:
        for attachment in entry.get("attachments", []):
            exported = os.path.join(raw, attachment.get("exportedFileName", ""))
            human = SUFFIX.sub("", attachment.get("suggestedHumanReadableName", ""))
            if not os.path.isfile(exported) or not human:
                continue
            base = os.path.splitext(human)[0]
            if human.lower().endswith((".png", ".jpg", ".jpeg", ".heic")):
                shutil.copy(exported, os.path.join(target, human))
                images.append(human)
            elif base == "audit":
                audits.append((device, open(exported, encoding="utf-8", errors="replace").read()))
            elif base == "note":
                notes.append((device, open(exported, encoding="utf-8", errors="replace").read().strip()))

    images = sorted(set(images))
    lines = [f"## {device}", ""]
    if not images:
        lines.append("Aucune capture : le test a échoué avant la première capture.")
    else:
        width = 150 if "watch" in folder else 230
        cells = [f'<td align="center"><img src="{folder}/{name}" width="{width}"><br>'
                 f'<sub>{os.path.splitext(name)[0]}</sub></td>' for name in images]
        per_row = 4
        lines.append("<table>")
        for i in range(0, len(cells), per_row):
            lines.append("<tr>" + "".join(cells[i:i + per_row]) + "</tr>")
        lines.append("</table>")
    lines.append("")
    sections.append("\n".join(lines))

shutil.rmtree(os.path.join(out, "_raw"), ignore_errors=True)

readme = [
    f"# Captures — {os.environ.get('GITHUB_REF_NAME', '?')}",
    "",
    f"Commit `{os.environ.get('GITHUB_SHA', '?')[:7]}` · générées par le build « Captures » "
    "avec le plan de démo (`docs/exemple-plan.json`).",
    "",
    *sections,
]
if notes:
    readme += ["## Étapes sautées", ""] + [f"- {device} : {text}" for device, text in notes] + [""]
if audits:
    readme += ["## Audit d'accessibilité d'Apple (iPhone)", "",
               "Problèmes signalés par l'audit intégré à Xcode. Ils ne bloquent pas le build.", ""]
    for device, text in audits:
        readme += [f"<details><summary>{device}</summary>", "", text, "", "</details>", ""]

with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(readme))
print("\n".join(readme)[:3000])
