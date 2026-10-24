"""Run every golden row through each prompt variant with the on-device model.

Run with: uv run --project eval python eval/run.py [--variants rules fewshot] [--schema text] [--limit 20]
Writes eval/runs/<timestamp>-<schema>.parquet (git-ignored) and prints a summary.
"""

import argparse
import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import apple_fm_sdk as fm
import pandas as pd

from metrics import summarize
from protect import protect
from restore import keep_layout, keep_writer_style, match_quote_style, placeholder_problems, restore

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "golden" / "golden.jsonl"
VARIANTS = Path(__file__).resolve().parent / "variants"
RUNS = Path(__file__).resolve().parent / "runs"

TONES = {"keep": "keep the writer's tone"}
PLACEHOLDER_RULE = "The message contains placeholders: {list}. Copy each one exactly once, unchanged, in a natural position."


LEADING_MENTION_RULE = "The message starts with ⟦T1⟧, which addresses someone: keep ⟦T1⟧ at the start."
LEADING_RULE = "The message starts with ⟦T1⟧: keep ⟦T1⟧ at the start."


def build_instructions(template: str, tone: str, placeholders: int, leading_mention: bool = False,
                       leading_token: bool = False) -> str:
    # Only mention placeholders when the draft has some (otherwise the model invents them), and name each one.
    names = ", ".join(f"⟦T{n}⟧" for n in range(1, placeholders + 1))
    rule = PLACEHOLDER_RULE.format(list=names) + "\n" if placeholders else ""
    # The model's most common placeholder failure is dropping a leading addressee, emoji or bold label.
    if leading_mention:
        rule += LEADING_MENTION_RULE + "\n"
    elif leading_token:
        rule += LEADING_RULE + "\n"
    return template.replace("{tone}", TONES[tone]).replace("{placeholders}\n", rule)


@fm.generable("A rewritten Slack message")
class RewriteTextOnly:
    text: str = fm.guide("The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")


@fm.generable("One change made to the message")
class Change:
    original: str = fm.guide("The original words")
    replacement: str = fm.guide("The new words")


@fm.generable("A rewritten Slack message and its main changes")
class Rewrite:
    text: str = fm.guide("The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")
    changes: list[Change] = fm.guide("The most important changes", max_items=5)


@fm.generable("A checked and rewritten Slack message")
class RewriteChecked:
    has_mistakes: bool = fm.guide(
        "True only if the message has spelling, grammar, punctuation or wrong-word mistakes, "
        "shorthand to expand, or a sentence that is hard to understand. False if it is already clear and correct."
    )
    text: str = fm.guide("The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")


@fm.generable("A rewritten Slack message, line by line")
class RewriteLines:
    lines: list[str] = fm.guide(
        "The rewritten message, one entry for each line of the original message, in the same order. "
        "Keep list markers at the start of their lines. Copy every ⟦Tn⟧ placeholder exactly once."
    )


@fm.generable("A Slack message's mistakes and its rewrite")
class RewriteWithMistakes:
    mistakes: list[str] = fm.guide(
        "Each misspelled word, wrong word, grammar error, missing punctuation or shorthand, copied exactly "
        "from the message. Empty if the message is already clear and correct.",
        max_items=10,
    )
    text: str = fm.guide("The rewritten message. Copy every ⟦Tn⟧ placeholder exactly once.")


SCHEMAS = {"text": RewriteTextOnly, "changes": Rewrite, "checked": RewriteChecked, "lines": RewriteLines,
           "mistakes": RewriteWithMistakes}


MISTAKES_LOG: list[list[str]] = []  # per attempt, for offline analysis


def length_ok(output: str, source: str) -> bool:
    ratio = len(output) / max(len(source), 1)
    return 0.6 <= ratio <= 1.6


def nonblank_lines(text: str) -> int:
    return sum(1 for line in text.split("\n") if line.strip())


def validate(output: str, protected) -> list[str]:
    if not output.strip():
        return ["empty"]
    problems = placeholder_problems(output, protected)
    if not length_ok(output, protected.text):
        problems.append("length")
    # Line breaks are Slack syntax too (FR-4): a merged or dropped line fails, so the draft is kept.
    if nonblank_lines(output) < nonblank_lines(protected.text):
        problems.append("lines")
    return problems


async def generate(model, instructions: str, prompt: str, schema, temperature: float) -> str:
    session = fm.LanguageModelSession(instructions=instructions, model=model)  # new session per request
    # Cap the response so a looping generation fails fast instead of filling the context.
    options = fm.GenerationOptions(temperature=temperature, maximum_response_tokens=len(prompt) // 2 + 200)
    result = await session.respond(prompt, generating=schema, options=options)
    if getattr(result, "has_mistakes", True) is False:
        return prompt  # the model judged the draft correct: keep it exactly
    if isinstance(result, RewriteWithMistakes):
        # Listing mistakes first makes the model look before it rewrites; the list itself is not used.
        MISTAKES_LOG.append(list(result.mistakes))
    if isinstance(result, RewriteLines):
        return keep_layout("\n".join(result.lines), prompt)
    return result.text


async def polish_row(model, row: dict, template: str, tone: str, schema, keep_style: bool, temperature: float) -> dict:
    """The Phase 2 pipeline in miniature: protect, generate, validate, retry once at 0, restore."""
    protected = protect(row["input"])
    leading = protected.text.startswith("⟦T1⟧")
    leading_mention = leading and protected.tokens[0].startswith(("@", "<@"))
    instructions = build_instructions(template, tone, len(protected.tokens), leading_mention, leading and not leading_mention)
    record = {"tokens": len(protected.tokens), "attempts": 0, "error": None, "raw": None, "problems": [], "final_problems": []}
    start = time.perf_counter()
    for temperature in (temperature, 0.0):
        record["attempts"] += 1
        try:
            raw = await generate(model, instructions, protected.text, schema, temperature)
        except fm.FoundationModelsError as error:
            record["error"] = type(error).__name__
            break
        problems = validate(raw, protected)
        if record["raw"] is None:
            record["raw"], record["problems"] = raw, problems
        record["final_problems"] = problems
        if not problems:
            text = keep_layout(raw, protected.text)
            text = keep_writer_style(text, protected.text) if keep_style else text
            record["output"] = restore(match_quote_style(text, protected.text), protected)
            break
    record["latency_s"] = time.perf_counter() - start
    if MISTAKES_LOG:
        record["mistakes"] = MISTAKES_LOG[0]
        MISTAKES_LOG.clear()
    record["fallback"] = "output" not in record
    record.setdefault("output", row["input"])  # never change the text on failure
    return record


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variants", nargs="+", default=sorted(p.stem for p in VARIANTS.glob("*.txt")))
    parser.add_argument("--schema", choices=SCHEMAS, default="text")
    parser.add_argument("--tone", choices=TONES, default="keep")
    parser.add_argument("--guardrails", choices=["default", "permissive"], default="default")
    parser.add_argument("--no-keep-style", dest="keep_style", action="store_false", help="skip contraction/term revert")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--ids", nargs="+")
    args = parser.parse_args()

    guardrails = {"default": fm.SystemLanguageModelGuardrails.DEFAULT,
                  "permissive": fm.SystemLanguageModelGuardrails.PERMISSIVE_CONTENT_TRANSFORMATIONS}[args.guardrails]
    model = fm.SystemLanguageModel(guardrails=guardrails)
    available, reason = model.is_available()
    if not available:
        print(f"Model not available: {reason}")
        return 1

    rows = [json.loads(line) for line in GOLDEN.read_text(encoding="utf-8").splitlines() if line.strip()]
    if args.ids:
        rows = [r for r in rows if r["id"] in args.ids]
    rows = rows[: args.limit]

    records = []
    for variant in args.variants:
        template = (VARIANTS / f"{variant}.txt").read_text(encoding="utf-8")
        for i, row in enumerate(rows, 1):
            result = await polish_row(model, row, template, args.tone, SCHEMAS[args.schema], args.keep_style, args.temperature)
            records.append({**row, "variant": variant, "schema": args.schema, "guardrails": args.guardrails,
                            "keep_style": args.keep_style, "temperature": args.temperature, **result})
            print(f"\r{variant}: {i}/{len(rows)}", end="", flush=True)
        print()

    df = pd.DataFrame(records)
    RUNS.mkdir(exist_ok=True)
    out = RUNS / f"{datetime.now():%Y%m%d-%H%M%S}-{args.schema}-{args.guardrails}-t{args.temperature}.parquet"
    df.to_parquet(out)
    print(f"Saved {out.relative_to(ROOT)}\n")
    print(summarize(df).to_string())
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
