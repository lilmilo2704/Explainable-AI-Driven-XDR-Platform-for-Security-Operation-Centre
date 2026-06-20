"""Warn when frontend mock fallback code changes.

The repository can use demo data, but failed real pipeline calls must not be
silently hidden by mock fallback.
"""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WATCH_TERMS = ("withFallback", "mockStore", "mockData", "fallback")


def main() -> int:
    targets = [ROOT / arg for arg in sys.argv[1:]] if len(sys.argv) > 1 else []
    if not targets:
        targets = [ROOT / "frontend" / "src" / "api" / "client.ts"]

    for path in targets:
        if not path.exists() or not path.is_file():
            continue
        if "frontend" not in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if any(term in text for term in WATCH_TERMS):
            rel = path.relative_to(ROOT)
            print(
                f"REMINDER: {rel} references mock or fallback behavior. "
                "Ensure real/demo/failure states are explicit."
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
