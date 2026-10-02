#!/usr/bin/env python3
"""Generate Era's AltStore source from published GitHub releases.

Two apps:
  Era      (de.malte.era)      - stable releases only
  Era Beta (de.malte.era.beta) - pre-releases only

An app is only listed once it has at least one version.
"""
import json, os, re, sys, urllib.request
from datetime import datetime

REPO = os.environ.get("GITHUB_REPOSITORY", "Malti2/Era")
API = f"https://api.github.com/repos/{REPO}/releases?per_page=100"
SOURCE_URL = "https://malti2.github.io/Era/source.json"
ICON_URL = "https://malti2.github.io/Era/icon.png"
MIN_VERSION = (27, 0, 0)

APPS = [
    {
        "name": "Era",
        "bundle": "de.malte.era",
        "subtitle": "Your music, organized your way.",
        "description": "A private-first offline library for released tracks, unreleased songs, demos, alternate versions, and personal audio files.",
        "tint": "#30D158",
        "channel": "stable",
    },
    {
        "name": "Era Beta",
        "bundle": "de.malte.era.beta",
        "subtitle": "Beta builds - newest features, may be unstable.",
        "description": "Beta channel for Era: try the newest features before they land in the stable release. Expect rough edges.",
        "tint": "#FF9F0A",
        "channel": "beta",
    },
]

def marketing_version(value):
    match = re.match(r"^[vV]?(\d+\.\d+\.\d+)", value)
    return match.group(1) if match else ""

def beta_version(value):
    v = value.strip().lstrip("vV")
    return v if re.match(r"^\d+\.\d+\.\d+-", v) else ""

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

def version_entry(release, ipa, version):
    notes = plain_notes(release.get("body") or "")
    return {
        "version": version,
        "date": release["published_at"][:10],
        "localizedDescription": notes,
        "releaseNotes": notes,
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": "18.0",
    }

request = urllib.request.Request(API, headers={"Accept":"application/vnd.github+json", "User-Agent":"Era-AltStore-Source"})
with urllib.request.urlopen(request) as response:
    releases = json.load(response)

buckets = {"stable": [], "beta": []}
for release in releases:
    if release.get("draft"):
        continue
    tag = release.get("tag_name", "")
    ipa = next((a for a in release.get("assets", []) if a.get("name") == "Era-unsigned.ipa"), None)
    if not ipa:
        continue
    if release.get("prerelease"):
        version = beta_version(tag)
        if version:
            buckets["beta"].append(version_entry(release, ipa, version))
    else:
        version = marketing_version(tag)
        if version and version_tuple(version) >= MIN_VERSION:
            buckets["stable"].append(version_entry(release, ipa, version))

for versions in buckets.values():
    versions.sort(key=lambda v: version_tuple(v["version"]), reverse=True)

apps = []
for cfg in APPS:
    versions = buckets[cfg["channel"]]
    if not versions:
        continue
    apps.append({
        "name": cfg["name"],
        "bundleIdentifier": cfg["bundle"],
        "developerName": "Malte",
        "subtitle": cfg["subtitle"],
        "localizedDescription": cfg["description"],
        "iconURL": ICON_URL,
        "tintColor": cfg["tint"],
        "category": "music",
        "versions": versions,
    })

if not apps:
    raise SystemExit("No eligible Era IPA releases found")

source = {
    "name": "Era",
    "subtitle": "Private-first offline music library",
    "description": "Official AltStore source for Era, an offline music library for iPhone and iPad.",
    "iconURL": ICON_URL,
    "website": "https://github.com/Malti2/Era",
    "tintColor": "#30D158",
    "featuredApps": ["de.malte.era"],
    "apps": apps,
    "news": []
}
os.makedirs("docs", exist_ok=True)
with open("docs/source.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
    f.write("\n")
summary = ", ".join(f"{a['name']}: {len(a['versions'])}" for a in apps)
print(f"Wrote {summary} to docs/source.json")
