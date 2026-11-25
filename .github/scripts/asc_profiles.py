#!/usr/bin/env python3
"""Prépare la signature TestFlight via l'API App Store Connect (#89).

Pour chaque identifiant d'app (iPhone, montre) :
  - crée l'identifiant s'il manque, active HealthKit ;
  - recrée un profil « App Store » lié au certificat de distribution importé ;
  - installe le profil pour Xcode.
Écrit les noms des profils dans $GITHUB_ENV (COACH_PROFILE, WATCH_PROFILE).
N'affiche jamais la clé ni ses identifiants.

Usage : asc_profiles.py <numéro de série du certificat> <id iPhone> <id montre>
Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
"""
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

import jwt  # pyjwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = pathlib.Path(os.environ["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            errs = json.loads(detail).get("errors", [])
            detail = " | ".join(f"{x.get('title')}: {x.get('detail')}" for x in errs)
        except ValueError:
            pass
        sys.exit(f"error: API App Store Connect {method} {path.split('?')[0]} -> {e.code} {detail}")


def norm(serial):
    return serial.replace(":", "").upper().lstrip("0")


def certificate_id(serial):
    res = call("GET", "/certificates?limit=200")
    for c in res.get("data", []):
        if norm(c["attributes"].get("serialNumber", "")) == norm(serial):
            return c["id"], c["attributes"].get("certificateType")
    sys.exit("error: le certificat importé n'est pas dans le compte développeur (secret BUILD_CERT_P12 ?)")


def bundle_id(identifier, name):
    res = call("GET", f"/bundleIds?filter[identifier]={identifier}&limit=200")
    for b in res.get("data", []):
        if b["attributes"]["identifier"] == identifier:
            return b["id"]
    print(f"Création de l'identifiant {identifier}")
    res = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    return res["data"]["id"]


def ensure_healthkit(bid):
    caps = call("GET", f"/bundleIds/{bid}/bundleIdCapabilities")
    if any(c["attributes"].get("capabilityType") == "HEALTHKIT" for c in caps.get("data", [])):
        return
    print("Activation de HealthKit")
    call("POST", "/bundleIdCapabilities", {"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": "HEALTHKIT"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})


def fresh_profile(name, bid, cert):
    old = call("GET", f"/profiles?filter[name]={urllib.request.quote(name)}&limit=200")
    for p in old.get("data", []):
        if p["attributes"]["name"] == name:
            call("DELETE", f"/profiles/{p['id']}")
    res = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": cert}]}}}})
    attrs = res["data"]["attributes"]
    content = base64.b64decode(attrs["profileContent"])
    for folder in ("Library/MobileDevice/Provisioning Profiles",
                   "Library/Developer/Xcode/UserData/Provisioning Profiles"):
        d = pathlib.Path.home() / folder
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{attrs['uuid']}.mobileprovision").write_bytes(content)
    print(f"Profil prêt : {name}")


def main():
    serial, app_id, watch_id = sys.argv[1:4]
    cert, kind = certificate_id(serial)
    print(f"Certificat trouvé ({kind})")
    names = {}
    for env, identifier, label in (("COACH_PROFILE", app_id, "Coach"), ("WATCH_PROFILE", watch_id, "Coach Watch")):
        bid = bundle_id(identifier, label)
        ensure_healthkit(bid)
        names[env] = f"Coach TestFlight {identifier}"
        fresh_profile(names[env], bid, cert)
    with open(os.environ["GITHUB_ENV"], "a") as f:
        for k, v in names.items():
            f.write(f"{k}={v}\n")


if __name__ == "__main__":
    main()
