#!/usr/bin/env python3
"""Choisit les simulateurs pour les captures et écrit leurs identifiants dans $GITHUB_ENV.

iPhone standard + petit iPhone (SE), grande montre + petite montre, sur le système le plus récent.
Un appareil introuvable est simplement sauté (variable absente).
"""
import json
import os
import re
import subprocess


def simctl(*args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", *args, "-j"]))


devices = []
for runtime, items in simctl("devices", "available")["devices"].items():
    match = re.search(r"SimRuntime\.(iOS|watchOS)-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(2)), int(match.group(3)))
    for item in items:
        devices.append({"platform": match.group(1), "version": version,
                        "name": item["name"], "udid": item["udid"]})
devices.sort(key=lambda d: d["version"], reverse=True)


def pick(platform, patterns):
    for pattern in patterns:
        for device in devices:
            if device["platform"] == platform and re.fullmatch(pattern, device["name"]):
                return device
    return None


def create(name):
    """Crée le simulateur s'il existe comme modèle mais pas comme appareil."""
    types = [t for t in simctl("devicetypes")["devicetypes"] if t["name"] == name]
    runtimes = [r for r in simctl("runtimes")["runtimes"]
                if r.get("isAvailable") and r["identifier"].split(".")[-1].startswith("iOS")]
    if not types or not runtimes:
        return None
    runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
    try:
        udid = subprocess.check_output(
            ["xcrun", "simctl", "create", name, types[0]["identifier"], runtimes[0]["identifier"]],
            stderr=subprocess.STDOUT).decode().strip()
        return {"name": name, "udid": udid}
    except subprocess.CalledProcessError as error:
        print(f"Création impossible ({name}) : {error.output.decode().strip()}")
        return None


choices = {
    "IOS_STD": pick("iOS", [r"iPhone 17", r"iPhone 16", r"iPhone \d+"]),
    "IOS_SMALL": pick("iOS", [r"iPhone SE \(3rd generation\)", r"iPhone SE.*"])
                 or create("iPhone SE (3rd generation)"),
    "WATCH_L": pick("watchOS", [r"Apple Watch Series \d+ \(46mm\)", r"Apple Watch Series \d+ \(45mm\)",
                                r"Apple Watch Ultra.*"]),
    "WATCH_S": pick("watchOS", [r"Apple Watch SE.*\(40mm\)", r"Apple Watch Series \d+ \(42mm\)",
                                r"Apple Watch Series \d+ \(41mm\)", r"Apple Watch.*\(4[0-2]mm\)"]),
}

with open(os.environ.get("GITHUB_ENV", "/dev/stdout"), "a") as env:
    for key, device in choices.items():
        if device:
            print(f"{key}: {device['name']} ({device['udid']})")
            env.write(f"{key}_ID={device['udid']}\n{key}_NAME={device['name']}\n")
        else:
            print(f"{key}: aucun simulateur trouvé")
