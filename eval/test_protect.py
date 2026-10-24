"""Protect/restore tests. Run with: uv run --project eval python eval/test_protect.py"""

import json
import sys
from pathlib import Path

from protect import protect
from restore import keep_layout, keep_writer_style, match_quote_style, placeholder_problems, restore

GOLDEN = Path(__file__).resolve().parent.parent / "golden" / "golden.jsonl"

# (input, tokens protect() must find, in order)
CASES = [
    ("<@U02ABC123> can u check", ["<@U02ABC123>"]),
    ("see <#C0123ABC|general> and #platform-eng", ["<#C0123ABC|general>", "#platform-eng"]),
    ("<!here> deploy at 5", ["<!here>"]),
    ("@Alex Morgan is it required", ["@Alex Morgan"]),
    ("@Maria Lopez Garcia and @Tom Becker pls sync", ["@Maria Lopez Garcia", "@Tom Becker"]),
    ("@Jordan can you check", ["@Jordan"]),
    ("@Sam We can remove it", ["@Sam"]),
    ("thanks for the fix @Chris Park.", ["@Chris Park"]),
    ("@here the env is down", ["@here"]),
    ("mail dev@example.com today", ["dev@example.com"]),
    ("docs at https://example.com/a?b=1. thanks", ["https://example.com/a?b=1"]),
    ("(see https://example.com/x)", ["https://example.com/x"]),
    ("<https://example.com/doc|the doc> is up", ["<https://example.com/doc|the doc>"]),
    ("nice :tada::skin-tone-2: and :+1:", [":tada::skin-tone-2:", ":+1:"]),
    ("run `kubectl get pods` now", ["`kubectl get pods`"]),
    ("try:\n```\nfoo = 'bar'\n```\nthen tell me", ["```\nfoo = 'bar'\n```"]),
    ("this is *really* urgent", ["*really*"]),
    ("_please_ check ~old~ ~~older~~", ["_please_", "~old~", "~~older~~"]),
    ("*@Sam* look", ["*@Sam*"]),
    ("snake_case and 5 * 3 and ~5 min", []),
    ("- item one\n• item two\n1. item three", []),
    ("issue #42 and C# code", ["#42"]),
    ("ratio 3:2 at 10:30", []),
]


def main() -> int:
    failures = 0
    for text, want in CASES:
        got = protect(text).tokens
        if got != want:
            failures += 1
            print(f"FAIL tokens {text!r}: got {got}, want {want}")

    dictionary = protect("ask Kubeflow and kubeflow-ui", dictionary=["Kubeflow"])
    if dictionary.tokens != ["Kubeflow"]:
        failures += 1
        print(f"FAIL dictionary: {dictionary.tokens}")

    p = protect("⟦x <@U1> and #a")
    if placeholder_problems("⟦x ⟦T1⟧ and ⟦T2⟧", p) or placeholder_problems("⟦x ⟦T2⟧ and ⟦T1⟧", p):
        failures += 1
        print("FAIL valid output flagged")
    for bad, why in [("⟦T1⟧ and", "missing"), ("⟦T1⟧ ⟦T1⟧ ⟦T2⟧", "duplicated"), ("⟦T1⟧ ⟦T2⟧ ⟦T3⟧", "unknown"),
                     ("⟦T1⟧ [T2]", "missing")]:
        if not any(why in problem for problem in placeholder_problems(bad, p)):
            failures += 1
            print(f"FAIL {why} not flagged in {bad!r}")

    quotes = [
        ("I'm sure it's \"done\"", "I’m sure it’s “done”", True),
        ("I’m sure it’s “done”", "I'm sure it's \"done\"", False),
        ("the '90s and 'quoted' word", "the ’90s and ‘quoted’ word", True),
    ]
    for output, want, curly in quotes:
        got = match_quote_style(output, "’" if curly else "'")
        if got != want:
            failures += 1
            print(f"FAIL quotes {output!r}: got {got!r}, want {want!r}")

    styles = [
        ("I will post the doc.", "i'll post the doc", "I'll post the doc."),
        ("I will send the configuration. It is done.", "I’ll send the config, it’s done", "I’ll send the config. It’s done."),
        ("Do not merge yet.", "dont merge yet", "Do not merge yet."),  # no contraction in the draft
        ("That is the document I wrote.", "That's the docs i wrote", "That's the document I wrote."),
    ]
    for output, source, want in styles:
        if (got := keep_writer_style(output, source)) != want:
            failures += 1
            print(f"FAIL style {output!r}: got {got!r}, want {want!r}")

    layouts = [
        ("One.\nTwo.", "one\n\ntwo", "One.\n\nTwo."),
        ("Intro:\n- a\n- b", "intro:\n  - a\n  - b", "Intro:\n  - a\n  - b"),
        ("One. Two.", "one\n\ntwo", "One. Two."),  # merged lines: left for validation to reject
    ]
    for output, source, want in layouts:
        if (got := keep_layout(output, source)) != want:
            failures += 1
            print(f"FAIL layout {output!r}: got {got!r}, want {want!r}")

    rows = [json.loads(line) for line in GOLDEN.read_text(encoding="utf-8").splitlines() if line.strip()]
    for row in rows:
        for field in ("input", "expected"):
            p = protect(row[field])
            if restore(p.text, p) != row[field]:
                failures += 1
                print(f"FAIL round trip {row['id']} {field}")
        # Tokens protected in the input must survive verbatim in expected.
        for token in protect(row["input"]).tokens:
            if token not in row["expected"]:
                failures += 1
                print(f"FAIL {row['id']}: token {token!r} missing from expected")

    print(f"{len(CASES)} token cases, {len(rows)} golden rows round-tripped, {failures} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
