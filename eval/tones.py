"""Score golden runs per tone (FR-8). The golden `expected` values are written in the default tone, so the
other tones are scored against the Keep my tone run of the same prompt: how far they move from it, and in
which direction (length, contractions, exclamation marks).

Run with: uv run --project eval python eval/tones.py eval/runs/tones-v2-*.jsonl

Each file is a `polish-cli golden --tone T --prompt P` run; the `variant` and `tone` columns name it.
"""

import argparse
import re
from pathlib import Path

import pandas as pd

from metrics import summarize, word_error_rate

# Possessives ('s) count too; they barely move between tones, so the difference still shows contractions.
CONTRACTION = re.compile(r"\b\w+['’](?:ll|re|ve|d|s|t|m)\b", re.IGNORECASE)


def per_100_words(texts: pd.Series, pattern: re.Pattern) -> float:
    words = texts.str.split().str.len().sum()
    return 100 * texts.apply(lambda t: len(pattern.findall(t))).sum() / max(words, 1)


def tone_scores(run: pd.DataFrame, keep: pd.DataFrame | None) -> pd.Series:
    longer = run[run["input"].str.split().str.len() >= 20]
    correct = run[run["tags"].apply(lambda tags: "correct" in tags)]
    scores = {
        "length_ratio_20w+": (longer["output"].str.len() / longer["input"].str.len()).mean(),
        "contractions_per_100w": per_100_words(run["output"], CONTRACTION),
        "exclamations_per_100w": per_100_words(run["output"], re.compile("!")),
        "correct_rows_changed": (correct["output"] != correct["input"]).mean(),
    }
    if keep is not None:
        joined = run.merge(keep[["id", "output"]], on="id", suffixes=("", "_keep"))
        scores["change_vs_keep"] = sum(word_error_rate(o, k) for o, k in zip(joined["output"], joined["output_keep"])) / len(joined)
        shorter = joined["output"].str.len() <= 0.9 * joined["output_keep"].str.len()
        scores["shorter_than_keep_10pct"] = shorter.mean()
    return pd.Series(scores)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()

    runs = []
    for path in args.runs:
        df = pd.read_json(path, lines=True)
        # Swift's JSONEncoder leaves out nil fields: no `error` key means the row had no error.
        df["error"] = df["error"].where(df["error"].notna(), None) if "error" in df else None
        df["run"] = df["variant"] + "/" + df["tone"]
        runs.append(df)
    frame = pd.concat(runs, ignore_index=True)

    columns = ["id", "input", "expected", "tags", "run", "tokens", "error", "problems", "final_problems",
               "output", "fallback", "latency_s"]
    base = summarize(frame[columns], by="run")
    # Keep my tone always uses the v1 prompt; the restyle prompts (v2+) only cover the other tones.
    keep = next((df for df in runs if df["tone"].iat[0] == "keep"), None)
    extra = pd.DataFrame({
        df["run"].iat[0]: tone_scores(df, keep if df["tone"].iat[0] != "keep" else None) for df in runs
    })
    rows = ["placeholder_integrity_first", "placeholder_integrity_after_retry", "fallbacks", "generation_errors",
            "unchanged_when_correct", "wer_fix_rows", "fix_rows_left_unchanged", "latency_p90_le60w_s"]
    table = pd.concat([base.loc[rows], extra])
    order = sorted(table.columns, key=lambda r: (r.split("/")[0], ["keep", "casual", "professional", "concise"].index(r.split("/")[1])))
    print(table[order].to_string(float_format=lambda v: f"{v:.3f}"))


if __name__ == "__main__":
    main()
