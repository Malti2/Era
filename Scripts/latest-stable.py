#!/usr/bin/env python3
"""Reads release tags (one per line) from stdin, prints the highest vX.Y.Z as X.Y.Z (or nothing)."""
import re
import sys

versions = []
for line in sys.stdin:
    m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", line.strip())
    if m:
        versions.append(tuple(int(x) for x in m.groups()))
if versions:
    print("%d.%d.%d" % max(versions))
