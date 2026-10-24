"""Score Swift harness runs (polish-cli golden) next to Python runs (run.py) with the same metrics.

Run with: uv run --project eval python eval/compare.py --swift eval/runs/swift-*.jsonl --python eval/runs/<run>.parquet ...

Phase 2 exit check: every rate metric of every Swift run lies within 1 point of the range the Python runs span.
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

from metrics import summarize

# Rates compared in percentage points; the rest are shown for reference.
RATES = [
    "placeholder_integrity_first",
    "placeholder_integrity_after_retry",
    "unchanged_when_correct",
    "exact_match_fix_rows",
    "fix_rows_left_unchanged",
]
TOLERANCE = 0.01


def load(path: Path, label: str) -> pd.DataFrame:
    df = pd.read_json(path, lines=True) if path.suffix == ".jsonl" else pd.read_parquet(path)
    df["variant"] = label
    # Swift's JSONEncoder leaves out nil fields: no `error` key means the row had no error.
    df["error"] = df["error"].where(df["error"].notna(), None) if "error" in df else None
    return df


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--swift", nargs="+", type=Path, required=True)
    parser.add_argument("--python", nargs="+", type=Path, required=True)
    args = parser.parse_args()

    frames = [load(p, f"python-{i}") for i, p in enumerate(args.python, 1)]
    frames += [load(p, f"swift-{i}") for i, p in enumerate(args.swift, 1)]
    columns = ["id", "input", "expected", "tags", "variant", "tokens", "error", "problems", "final_problems",
               "output", "fallback", "latency_s"]
    table = summarize(pd.concat([f[columns] for f in frames], ignore_index=True))
    print(table.to_string(float_format=lambda v: f"{v:.3f}"))

    python = table[[c for c in table.columns if c.startswith("python")]]
    swift = table[[c for c in table.columns if c.startswith("swift")]]
    low, high = python.min(axis=1) - TOLERANCE, python.max(axis=1) + TOLERANCE
    outside = [(metric, run, swift.at[metric, run]) for metric in RATES for run in swift.columns
               if not low[metric] <= swift.at[metric, run] <= high[metric]]
    print()
    if outside:
        for metric, run, value in outside:
            print(f"OUTSIDE {metric} {run}: {value:.3f} (python {python.loc[metric].min():.3f}–{python.loc[metric].max():.3f})")
        return 1
    print(f"Every rate metric of every Swift run is within {TOLERANCE * 100:.0f} point of the Python runs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
