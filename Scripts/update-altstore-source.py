#!/usr/bin/env python3
"""Generate Era's AltStore source from published GitHub releases."""
import json, os, re, sys, urllib.request
from datetime import datetime

REPO = os.environ.get("GITHUB_REPOSITORY", "Malti2/Era")
API = f"https://api.github.com/repos/{REPO}/releases?per_page=100"
SOURCE_URL = "https://malti2.github.io/Era/source.json"
ICON_URL = "https://malti2.github.io/Era/icon.png"
MIN_VERSION = (27, 0, 0)

def marketing_version(value):
    match = re.match(r"^[vV]?(\d+\.\d+\.\d+)", value)
    return match.group(1) if match else ""

def version_tuple(value):
    normalized = marketing_version(value) or value.lstrip("vV")
    try: return tuple(int(x) for x in normalized.split("."))
    except ValueError: return (0,)

def plain_notes(markdown):
    lines = []
    for line in markdown.replace("\r", "").splitlines():
        line = re.sub(r"^#{1,6}\s*", "", line)
        line = re.sub(r"\*\*([^*]+)\*\*", r"\1", line)
        line = re.sub(r"`([^`]+)`", r"\1", line).strip()
        if line and line.lower() not in {"downloads", "download"}:
            lines.append(line)
    return "\n".join(lines).strip() or "See the GitHub release for details."

request = urllib.request.Request(API, headers={"Accept":"application/vnd.github+json", "User-Agent":"Era-AltStore-Source"})
with urllib.request.urlopen(request) as response:
    releases = json.load(response)
versions = []
for release in releases:
    tag = release.get("tag_name", "")
    version = marketing_version(tag)
    if not version or release.get("draft") or version_tuple(version) < MIN_VERSION:
        continue
    ipa = next((a for a in release.get("assets", []) if a.get("name") == "Era-unsigned.ipa"), None)
    if not ipa: continue
    notes = plain_notes(release.get("body") or "")
    versions.append({
        "version": version,
        "date": release["published_at"][:10],
        "localizedDescription": notes,
        "releaseNotes": notes,
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": "18.0"
    })
versions.sort(key=lambda v: version_tuple(v["version"]), reverse=True)
if not versions:
    raise SystemExit("No eligible Era IPA releases found")
source = {
    "name": "Era",
    "subtitle": "Private-first offline music library",
    "description": "Official AltStore source for Era, an offline music library for iPhone and iPad.",
    "iconURL": ICON_URL,
    "website": "https://github.com/Malti2/Era",
    "tintColor": "#30D158",
    "featuredApps": ["de.malte.era"],
    "apps": [{
        "name": "Era",
        "bundleIdentifier": "de.malte.era",
        "developerName": "Malte",
        "subtitle": "Your music, organized your way.",
        "localizedDescription": "A private-first offline library for released tracks, unreleased songs, demos, alternate versions, and personal audio files.",
        "iconURL": ICON_URL,
        "tintColor": "#30D158",
        "category": "music",
        "versions": versions
    }],
    "news": []
}
os.makedirs("docs", exist_ok=True)
with open("docs/source.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"Wrote {len(versions)} version(s) to docs/source.json; newest is {versions[0]['version']}")
