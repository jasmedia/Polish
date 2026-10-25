"""Score the change list (FR-9). It's built in code from the word diff, so every entry matches the rewrite;
what's left to check is how long the list gets and whether the reasons fit the mistakes the rows contain.

Run with: uv run --project eval python eval/changes.py eval/runs/<run>.jsonl ...

Each file is a `polish-cli golden` run (every run records `changes`).
"""

import argparse
from pathlib import Path

import pandas as pd

# Golden tags and the reasons a row with that mistake should list at least once. `typo` rows also hold
# chat shorthand (u, pls, thx), so either reason counts there.
EXPECTED_REASONS = {"typo": {"spelling", "shorthand"}, "homophone": {"wrong word"}}


def scores(df: pd.DataFrame) -> pd.Series:
    changed = df[df["output"] != df["input"]]
    counts = changed["changes"].str.len()
    reasons = changed["changes"].apply(lambda cs: {c["reason"] for c in cs})
    result = {
        "rows_changed": len(changed),
        "entries_per_changed_row_median": counts.median(),
        "entries_per_changed_row_p90": counts.quantile(0.9),
        "changed_rows_over_10_entries": (counts > 10).mean(),
        "latency_p50_s": df["latency_s"].median(),
        "latency_p90_s": df["latency_s"].quantile(0.9),
    }
    for tag, expected in EXPECTED_REASONS.items():
        tagged = changed["tags"].apply(lambda tags: tag in tags)
        name = "_or_".join(sorted(reason.replace(" ", "_") for reason in expected))
        result[f"{tag}_rows_listing_{name}"] = reasons[tagged].apply(lambda r: bool(r & expected)).mean()
    entries = [c for cs in changed["changes"] for c in cs]
    for reason, share in pd.Series([c["reason"] for c in entries]).value_counts(normalize=True).items():
        result[f"share_{reason.replace(' ', '_')}"] = share
    return pd.Series(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    table = pd.DataFrame({path.stem: scores(pd.read_json(path, lines=True)) for path in args.runs})
    pd.set_option("display.float_format", "{:.3f}".format)
    print(table.to_string())


if __name__ == "__main__":
    main()
