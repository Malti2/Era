#!/usr/bin/env python3
import json, re, sys, urllib.request
path = sys.argv[1] if len(sys.argv) > 1 else "docs/source.json"
with open(path, encoding="utf-8") as f: source = json.load(f)
def need(obj, key, kind):
    assert key in obj, f"Missing {key}"
    assert isinstance(obj[key], kind), f"{key} must be {kind.__name__}"
for key in ("name", "subtitle", "description", "iconURL", "tintColor"):
    need(source, key, str)
need(source, "apps", list); assert source["apps"], "apps cannot be empty"
for app in source["apps"]:
    for key in ("name", "bundleIdentifier", "developerName", "subtitle", "localizedDescription", "iconURL", "tintColor"):
        need(app, key, str)
    assert re.fullmatch(r"[A-Za-z0-9.-]+", app["bundleIdentifier"])
    need(app, "versions", list); assert app["versions"], "versions cannot be empty"
    seen = set()
    for version in app["versions"]:
        for key in ("version", "date", "downloadURL", "minOSVersion", "localizedDescription"):
            need(version, key, str)
        need(version, "size", int); assert version["size"] > 0
        assert version["version"] not in seen, "duplicate version"
        seen.add(version["version"])
        assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", version["date"])
        assert version["downloadURL"].startswith("https://")
        assert version["downloadURL"].endswith(".ipa")
print(f"Valid AltStore source: {len(source['apps'])} app(s), {len(source['apps'][0]['versions'])} version(s)")
