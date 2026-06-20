"""Warn when frontend files appear to call the ML service directly.

This hook is intentionally read-only. It is suitable for manual invocation by
future agents or by a Codex hook runner that passes changed paths as arguments.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FRONTEND = ROOT / "frontend"
ML_PATTERNS = [
    re.compile(r"localhost:5000", re.IGNORECASE),
    re.compile(r"127\.0\.0\.1:5000", re.IGNORECASE),
    re.compile(r"ml-service", re.IGNORECASE),
    re.compile(r"/predict-(event|run|run-csv)", re.IGNORECASE),
    re.compile(r"/analyze-window", re.IGNORECASE),
]


def iter_targets(args: list[str]) -> list[Path]:
    if args:
        return [ROOT / arg for arg in args if (ROOT / arg).is_file()]
    if not FRONTEND.exists():
        return []
    return [
        path
        for path in FRONTEND.rglob("*")
        if path.suffix.lower() in {".ts", ".tsx", ".js", ".jsx"}
        and "node_modules" not in path.parts
    ]


def main() -> int:
    findings: list[str] = []
    for path in iter_targets(sys.argv[1:]):
        if not path.is_relative_to(FRONTEND):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern in ML_PATTERNS:
            if pattern.search(text):
                findings.append(str(path.relative_to(ROOT)))
                break

    if findings:
        print("WARNING: frontend may be calling ML service directly:")
        for item in findings:
            print(f"- {item}")
        print("Preserve service direction: frontend -> backend -> ml-service.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
