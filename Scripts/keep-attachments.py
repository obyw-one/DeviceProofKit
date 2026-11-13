#!/usr/bin/env python3
"""Keep the device proof's screen recording on passing test runs.

Usage: keep-attachments.py <Project.xcodeproj> [<scheme> ...]

XcodeGen 2.46 writes neither `systemAttachmentLifetime` nor
`preferredScreenCaptureFormat` into a scheme's TestAction, so a passing run
discards its recording (shikki-client's iPad run kept 1.1 MB, no video).
`check.py` needs that recording on every run, so this runs after
`xcodegen generate` (project.yml `options.postGenCommand`) and sets
`systemAttachmentLifetime = "keepAlways"` on each named shared scheme's
TestAction — or, with no scheme named, on every shared scheme that has one.

Idempotent; fails loudly if a named scheme, or every scheme's TestAction, is
missing. Standard library only.
"""
from __future__ import annotations

import pathlib
import re
import sys

KEEP = 'systemAttachmentLifetime = "keepAlways"'


def keep(scheme: pathlib.Path) -> str:
    text = scheme.read_text()
    if "<TestAction" not in text:
        return "no TestAction"
    if KEEP in text:
        return "already keepAlways"
    text = re.sub(r'\s*systemAttachmentLifetime = "[^"]*"', "", text)
    text = re.sub(r"<TestAction(\s)", lambda m: f"<TestAction{m.group(1)}      {KEEP}\n", text, count=1)
    scheme.write_text(text)
    return "set keepAlways"


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    project = pathlib.Path(sys.argv[1])
    schemes_dir = project / "xcshareddata" / "xcschemes"
    names = sys.argv[2:]
    schemes = [schemes_dir / f"{n}.xcscheme" for n in names] if names else sorted(schemes_dir.glob("*.xcscheme"))
    if not schemes:
        print(f"keep-attachments: no shared scheme in {schemes_dir}", file=sys.stderr)
        return 1
    changed = 0
    for scheme in schemes:
        if not scheme.exists():
            print(f"keep-attachments: {scheme} not found", file=sys.stderr)
            return 1
        result = keep(scheme)
        if result == "no TestAction" and names:
            print(f"keep-attachments: no <TestAction> in {scheme}", file=sys.stderr)
            return 1
        if result != "no TestAction":
            changed += 1
        print(f"keep-attachments: {scheme.name}: {result}")
    if changed == 0:
        print(f"keep-attachments: no scheme in {schemes_dir} has a TestAction", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
