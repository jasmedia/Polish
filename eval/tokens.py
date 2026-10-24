"""Measure token cost of instructions, schema and golden inputs; derive the chunking budget.

Run with: uv run --project eval python eval/tokens.py
"""

import asyncio
import json
import statistics
import sys

import apple_fm_sdk as fm

from protect import protect
from run import GOLDEN, SCHEMAS, VARIANTS, build_instructions

BUDGET_SHARE = 0.7  # chunk when a request would use more than ~70% of the context


async def main() -> int:
    model = fm.SystemLanguageModel()
    context = model.context_size
    print(f"context_size: {context} tokens\n")

    schema_tokens = {name: await model.token_count(schema.generation_schema()) for name, schema in SCHEMAS.items()}
    for name, tokens in schema_tokens.items():
        print(f"schema {name}: {tokens} tokens")

    for path in sorted(VARIANTS.glob("*.txt")):
        text = build_instructions(path.read_text(encoding="utf-8"), "keep", 3)
        print(f"instructions {path.stem}: {await model.token_count(instructions=text)} tokens")

    rows = [json.loads(line) for line in GOLDEN.read_text(encoding="utf-8").splitlines() if line.strip()]
    per_word = []
    for row in rows:
        text = protect(row["input"]).text
        tokens = await model.token_count(text)
        per_word.append(tokens / max(len(row["input"].split()), 1))
    ratio = statistics.mean(per_word)
    print(f"\ngolden inputs: {ratio:.2f} tokens per word on average (max {max(per_word):.2f})")

    instructions = build_instructions((VARIANTS / "rules2.txt").read_text(encoding="utf-8"), "keep", 3)
    fixed = await model.token_count(instructions=instructions) + schema_tokens["mistakes"]
    # The output is about as long as the input (up to +60%), and both share the context.
    input_budget = int((context * BUDGET_SHARE - fixed) / 2.6)
    print(f"fixed cost (rules2 + mistakes schema): {fixed} tokens")
    print(f"input budget before chunking: {input_budget} tokens ≈ {int(input_budget / ratio)} words")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
