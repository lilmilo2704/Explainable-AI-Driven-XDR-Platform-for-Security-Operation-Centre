"""Read-only protected-path checker for planned write sets."""

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROTECTED = [
    "ml-service/models/teachers/**",
    "ml-service/models/surrogates/**",
    "ml-service/models/metadata/**",
    "frontend/public/model-explanations/**",
    "lab-telemetry/exports/dataset-releases/**",
    "lab-telemetry/screenshots/**",
]


def normalize(path: str) -> str:
    try:
        return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.replace("\\", "/")


def main() -> int:
    blocked: list[str] = []
    for raw in sys.argv[1:]:
        rel = normalize(raw)
        if any(fnmatch.fnmatch(rel, pattern) for pattern in PROTECTED):
            blocked.append(rel)
    if blocked:
        print("BLOCKED protected paths:")
        for path in blocked:
            print(f"- {path}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
