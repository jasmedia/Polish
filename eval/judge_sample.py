"""Draw the judge-pass sample from a run: 50 fix rows (seeded) with input, expected and output.

Run with: uv run --project eval python eval/judge_sample.py eval/runs/<run>.parquet
Writes eval/runs/judge-sample.jsonl. A judge scores each row 0/1 on:
  meaning   - facts, names, numbers and requests unchanged; nothing added or lost
  voice     - still sounds like the writer (no new formality, greetings or hedging)
  corrected - every spelling, grammar and wrong-word mistake is fixed
Scores go in eval/judge/<prompt>.jsonl as {"id", "meaning", "voice", "corrected", "note"}.
"""

import json
import sys
from pathlib import Path

import pandas as pd

SAMPLE_SIZE = 50
SEED = 7


def main() -> int:
    df = pd.read_parquet(sys.argv[1])
    fixes = df[df["tags"].apply(lambda tags: "correct" not in tags)]
    sample = fixes.sample(n=min(SAMPLE_SIZE, len(fixes)), random_state=SEED).sort_values("id")
    out = Path(__file__).resolve().parent / "runs" / "judge-sample.jsonl"
    with out.open("w", encoding="utf-8") as f:
        for _, row in sample.iterrows():
            f.write(json.dumps({"id": row["id"], "input": row["input"], "expected": row["expected"],
                                "output": row["output"]}, ensure_ascii=False) + "\n")
    print(f"Wrote {len(sample)} rows to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
