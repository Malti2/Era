#!/usr/bin/env python3
"""Generate the private AltStore source for Claude nightly builds.

Every push to claude/nightly publishes a pre-release `nightly-<run>` with the unsigned IPA
(see .github/workflows/build.yml). This script lists all of them as versions of one app,
"Era Nightly". The result is uploaded as asset of the fixed release `nightly-source`:
  https://github.com/Malti2/Era/releases/download/nightly-source/nightly-source.json
The URL is intentionally not linked from the README or the public source.

usage: update-nightly-source.py [output.json]
"""
import json, os, re, sys, urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "Malti2/Era")
API = f"https://api.github.com/repos/{REPO}/releases?per_page=100&page={{page}}"
ICON_URL = "https://malti2.github.io/Era/icon.png"
TAG_RE = re.compile(r"^nightly-(\d+)$")
TRAILERS = ("co-authored-by:", "claude-session:")


def clean_notes(body):
    lines = [l.rstrip() for l in (body or "").replace("\r", "").splitlines()
             if not l.strip().lower().startswith(TRAILERS)]
    return "\n".join(lines).strip() or "Nightly build."


def build_source(releases):
    versions = []
    for release in releases:
        match = TAG_RE.match(release.get("tag_name", ""))
        ipa = next((a for a in release.get("assets", []) if a.get("name") == "Era-unsigned.ipa"), None)
        if release.get("draft") or not match or not ipa:
            continue
        title = (release.get("name") or "").strip()
        version = title if re.match(r"^\d+\.\d+\.\d+-nightly\.\d+", title) else f"0.0.0-nightly.{match.group(1)}"
        notes = clean_notes(release.get("body"))
        versions.append({
            "run": int(match.group(1)),
            "version": version,
            "date": release["published_at"][:10],
            "localizedDescription": notes,
            "releaseNotes": notes,
            "downloadURL": ipa["browser_download_url"],
            "size": ipa["size"],
            "minOSVersion": "18.0",
        })
    if not versions:
        raise SystemExit("No nightly IPA releases found")
    versions.sort(key=lambda v: v["run"], reverse=True)
    for v in versions:
        del v["run"]
    return {
        "name": "Era Nightly",
        "subtitle": "Claude nightly builds of Era",
        "description": "Private feed with every unsigned IPA built from the claude/nightly branch. Experimental - may be unstable.",
        "iconURL": ICON_URL,
        "website": f"https://github.com/{REPO}",
        "tintColor": "#5E5CE6",
        "featuredApps": ["de.malte.era.nightly"],
        "apps": [{
            "name": "Era Nightly",
            "bundleIdentifier": "de.malte.era.nightly",
            "developerName": "Malte",
            "subtitle": "Newest nightly build - may be unstable.",
            "localizedDescription": "Nightly builds of Era from the claude/nightly branch. Every build is kept; pick any version to install.",
            "iconURL": ICON_URL,
            "tintColor": "#5E5CE6",
            "category": "music",
            "versions": versions,
        }],
        "news": [],
    }


def fetch_releases():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Era-Nightly-Source"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    releases, page = [], 1
    while True:
        with urllib.request.urlopen(urllib.request.Request(API.format(page=page), headers=headers)) as response:
            batch = json.load(response)
        releases += batch
        if len(batch) < 100:
            return releases
        page += 1


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "nightly-source.json"
    source = build_source(fetch_releases())
    with open(out, "w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Wrote {len(source['apps'][0]['versions'])} nightly version(s) to {out}")
