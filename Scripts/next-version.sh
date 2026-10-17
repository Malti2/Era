#!/bin/bash
# Prints the next stable version: last non-prerelease tag + 1 patch, or the
# MARKETING_VERSION from project.yml when no stable release exists yet.
# Needs gh (GH_TOKEN set) and python3.
set -euo pipefail
BASE=$(grep -m1 'MARKETING_VERSION' project.yml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
LAST=$(gh release list --limit 100 --json tagName,isPrerelease -q '.[] | select(.isPrerelease | not) | .tagName' \
  | python3 Scripts/latest-stable.py)
if [ -n "$LAST" ]; then
  NEXT=$(echo "$LAST" | awk -F. '{print $1"."$2"."$3+1}')
else
  NEXT="$BASE"
fi
echo "stable version: $NEXT (base $BASE, last stable ${LAST:-none})" >&2
echo "$BASE $NEXT"
