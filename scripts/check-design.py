#!/usr/bin/env python3
"""Garde-fou du design système (#76).

Cherche dans les vues les valeurs tapées à la main au lieu des jetons du thème
(couleurs, tailles de texte, rayons, marges, espaces). Les jetons vivent dans
Shared/Theme.swift, Shared/DesignTokens.swift et Shared/Typography.swift.

Exception ponctuelle : ajouter en fin de ligne `// design-ok: raison`.

Usage : python3 scripts/check-design.py [--strict]
  sans option : liste les écarts, sort toujours avec 0 (avertissement) ;
  --strict    : sort avec 1 s'il reste un écart (bloquant).
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOLDERS = ["Coach", "CoachWatch", "Shared"]
# Fichiers qui définissent les jetons, ou qui ne dessinent pas d'interface.
SKIP = {
    "Shared/Theme.swift",
    "Shared/DesignTokens.swift",
    "Shared/Typography.swift",
    # Le petit bonhomme animé : illustration avec sa propre palette et sa géométrie.
    "Shared/ExerciseAnimation.swift",
}
SKIP_DIRS = ("Coach/Engine/",)

NUM = r"[0-9]+(?:\.[0-9]+)?"
RULES = [
    ("couleur en dur", re.compile(r"Color\(hex:|Color\.(white|black|red|green|blue|gray|orange|yellow|purple|pink)\b")),
    ("taille de texte en dur", re.compile(r"\.coach\(size:\s*" + NUM + r"|\.system\(size:\s*" + NUM)),
    # Un style d'Apple (.footnote, .caption…) donne une taille hors de l'échelle : utiliser un rôle
    # (Font.text, .detail, .label, .number…). Seules les définitions de Theme/Typography y ont droit.
    ("style de texte hors échelle", re.compile(r"\.coach\(\.[a-zA-Z0-9]+")),
    ("graisse très grasse (retirée par #40)", re.compile(r"weight:\s*\.(heavy|black)\b")),
    ("rayon en dur", re.compile(r"cornerRadius:\s*" + NUM + r"|\.card\([^)]*radius:\s*" + NUM)),
    ("marge de carte en dur", re.compile(r"\.card\([^)]*padding:\s*" + NUM)),
    ("hauteur minimale en dur", re.compile(r"minHeight:\s*" + NUM)),
    ("matière ou ombre hors thème", re.compile(r"\.(regular|thin|ultraThin|thick)Material|\.shadow\(")),
    ("marge en dur", re.compile(r"\.padding\((?:\.[a-zA-Z]+,\s*|\[[^\]]*\],\s*)?(?!0\))" + NUM + r"\)")),
    ("espace en dur", re.compile(r"spacing:\s*(?!0\b)" + NUM)),
]
EXEMPT = "design-ok"


def scan():
    findings = []
    for folder in FOLDERS:
        for path in sorted((ROOT / folder).rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if rel in SKIP or rel.startswith(SKIP_DIRS):
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//")[0] if EXEMPT not in line else ""
                for label, rule in RULES:
                    if rule.search(code):
                        findings.append((label, rel, number, line.strip()))
    return findings


def main():
    strict = "--strict" in sys.argv
    findings = scan()
    if not findings:
        print("Design : aucune valeur en dur dans les vues.")
        return 0
    totals = {}
    for label, *_ in findings:
        totals[label] = totals.get(label, 0) + 1
    print(f"Design : {len(findings)} valeur(s) en dur dans les vues (utiliser les jetons du thème).")
    for label, count in sorted(totals.items(), key=lambda kv: -kv[1]):
        print(f"  {count:4d}  {label}")
    phone = sum(1 for f in findings if not f[1].startswith("CoachWatch/"))
    print(f"  iPhone et Shared : {phone} · Montre : {len(findings) - phone}")
    print()
    for label, rel, number, line in findings:
        print(f"{rel}:{number}: {label} : {line[:110]}")
    return 1 if strict else 0


if __name__ == "__main__":
    sys.exit(main())
