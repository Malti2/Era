#!/usr/bin/env python3
"""Reads `simctl list devices available -j` from stdin, prints the UDID of the newest iPhone (Pro preferred)."""
import json
import re
import sys

devices = json.load(sys.stdin)["devices"]


def runtime_key(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if "iPhone" in d["name"]:
            cand = (runtime_key(runtime), "Pro" in d["name"], d["udid"])
            if best is None or cand > best:
                best = cand
if best is None:
    sys.exit("no iPhone simulator available")
print(best[2])
