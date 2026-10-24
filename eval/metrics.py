"""Scores for a run DataFrame from run.py. One row per (golden row, variant)."""

import pandas as pd

from restore import to_straight

PLACEHOLDER_PROBLEMS = ("missing", "duplicated", "unknown", "mangled")


def _placeholder_ok(problems) -> bool:
    return not any(p.startswith(PLACEHOLDER_PROBLEMS) for p in problems)


def _same(a: str, b: str, exact_quotes: bool) -> bool:
    return a == b if exact_quotes else to_straight(a) == to_straight(b)


def word_error_rate(hypothesis: str, reference: str) -> float:
    hyp, ref = hypothesis.split(), reference.split()
    previous = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        current = [i]
        for j, h in enumerate(hyp, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r != h)))
        previous = current
    return previous[-1] / max(len(ref), 1)


def score_rows(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    exact = df["tags"].apply(lambda tags: "apostrophe" in tags)
    df["is_correct_row"] = df["tags"].apply(lambda tags: "correct" in tags)
    df["has_tokens"] = df["tokens"] > 0
    df["generated"] = df["error"].isna()
    df["ph_ok_first"] = df["problems"].apply(_placeholder_ok)
    df["ph_ok_final"] = df["final_problems"].apply(_placeholder_ok)
    df["match_expected"] = [_same(o, e, x) for o, e, x in zip(df["output"], df["expected"], exact)]
    df["unchanged"] = [_same(o, i, x) for o, i, x in zip(df["output"], df["input"], exact)]
    df["wer"] = [word_error_rate(o, e) for o, e in zip(df["output"], df["expected"])]
    df["length_ratio"] = df["output"].str.len() / df["input"].str.len()
    df["words"] = df["input"].str.split().str.len()
    return df


def summarize(df: pd.DataFrame, by: str = "variant") -> pd.DataFrame:
    df = score_rows(df)

    def one(g: pd.DataFrame) -> pd.Series:
        tokened = g[g["has_tokens"] & g["generated"]]
        correct = g[g["is_correct_row"]]
        fixes = g[~g["is_correct_row"]]
        short = g[g["words"] <= 60]["latency_s"]
        return pd.Series({
            "rows": len(g),
            "placeholder_integrity_first": tokened["ph_ok_first"].mean(),
            "placeholder_integrity_after_retry": tokened["ph_ok_final"].mean(),
            "unchanged_when_correct": correct["unchanged"].mean(),
            "exact_match_fix_rows": fixes["match_expected"].mean(),
            "wer_fix_rows": fixes["wer"].mean(),
            "fix_rows_left_unchanged": fixes["unchanged"].mean(),
            "length_ratio": g["length_ratio"].mean(),
            "generation_errors": int((~g["generated"]).sum()),
            "fallbacks": int(g["fallback"].sum()),
            "latency_p50_s": g["latency_s"].quantile(0.5),
            "latency_p90_s": g["latency_s"].quantile(0.9),
            "latency_p90_le60w_s": short.quantile(0.9),
        })

    return df.groupby(by).apply(one, include_groups=False).T


def by_tag(df: pd.DataFrame) -> pd.DataFrame:
    df = score_rows(df).explode("tags")
    return df.groupby(["variant", "tags"]).agg(
        rows=("id", "size"), wer=("wer", "mean"), unchanged=("unchanged", "mean"),
        ph_ok_first=("ph_ok_first", "mean"), fallback=("fallback", "mean"),
    ).unstack("variant")
