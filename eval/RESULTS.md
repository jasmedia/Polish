# Phase 1 results

Prompt `prompts/v1.txt` (developed as `variants/rules2.txt`) with the `mistakes` schema, temperature 0.2, default guardrails, on the 210-row golden set (162 with mistakes, 48 correct, 86 with Slack tokens). macOS 27, on-device model, context size 8,192 tokens. Scored 2026-10-24.

## Exit check

Two full runs of the final configuration:

| Metric | Run A | Run B | Target |
| --- | --- | --- | --- |
| Placeholder integrity, first attempt | 100% | 100% | ≥ 99% |
| Unchanged when correct | 97.9% | 97.9% | ≥ 95% |
| p90 latency, inputs ≤ 60 words | 1.85 s | 1.78 s | ≤ 3 s |

All three targets are met. The pipeline never sends a broken placeholder: any output that fails validation falls back to the original.

| Other metrics | Run A | Run B |
| --- | --- | --- |
| WER vs `expected`, rows with mistakes | 0.245 | 0.253 |
| Exact match vs `expected`, rows with mistakes | 8.6% | 5.6% |
| Rows with mistakes returned unchanged | 10.5% | 8.0% |
| Fallbacks to the original (validation failed twice) | 6 | 7 |
| Generation errors | 1 | 1 |
| Mean length ratio (output / input) | 1.03 | 1.03 |
| Latency p50 / p90, all rows | 1.13 s / 2.26 s | 1.20 s / 2.44 s |

## Judge pass

50 rows with mistakes (seed 7, `judge_sample.py`) from run A, scored 0/1 by Claude in the development session. Scores and notes are in `judge/v1.jsonl`.

| Criterion | Score |
| --- | --- |
| Meaning kept | 50 / 50 |
| Voice kept | 48 / 50 (two dropped "pls", which reads as an order) |
| Fully corrected | 23 / 50 |

**Under-correction is the main weakness.** Meaning is never broken, but in about half of the drafts with mistakes the model fixes some and leaves others: comma splices, lowercase sentence starts, `a expired`, `from morning`, and partial edits in long multi-paragraph posts. The original v1 prompt has the same WER on this sample (0.238 against 0.241), so the gain in this phase is safety (integrity and unchanged-when-correct), not correction depth. That's the target for prompt v2.

## What changed from the starting prompt

Scores of the starting `prompts/v1.txt` (`variants/rules.txt`, text schema): integrity 97.7%, unchanged-when-correct 71%, 21 fallbacks.

| Change | Effect |
| --- | --- |
| Placeholder rule only when the draft has placeholders (`{placeholders}` slot) | The model stopped inventing `⟦T1⟧` in drafts without tokens: fallbacks 21 → 1 |
| Placeholder rule lists the exact placeholders (`⟦T1⟧, ⟦T2⟧`) | Shipped with the change above; not measured on its own |
| Extra rule when the draft starts with a mention: "keep ⟦T1⟧ at the start" | Fixed the last integrity failure pattern (dropped leading addressee): 98.8% → 100% |
| Prompt rules for contractions, casual words, synonyms, line breaks; shorthand split into "expand" and "keep" lists | Unchanged-when-correct 71% → ~81% |
| `mistakes` schema: the model lists the mistakes it sees, then rewrites (the list is not used) | Unchanged-when-correct ~81% → 92–96% at the same WER; works as a look-before-you-rewrite step |
| `keep_writer_style`: undo expansions of contractions and `doc`/`config`/`repo` that the draft used | Removes `I'll` → `I will` style edits |
| `keep_layout`: put the rewrite's lines back into the draft's blank-line layout when the counts match | Removes whitespace-only changes: → 97.9% |
| Validation: output must keep every non-blank line | Merged lines (dropped list intro, joined paragraphs) fall back instead of shipping |
| `maximum_response_tokens = len(prompt) / 2 + 200` | Looping generations fail fast instead of filling the context |

## What didn't work

| Tried | Result |
| --- | --- |
| `minimal` prompt | Lowest integrity (96.5%) and most fallbacks |
| Few-shot examples containing `⟦T1⟧` | The model invents placeholders again (22 fallbacks) |
| Few-shot without placeholders (`fewshot3`) | Best WER (0.21) but more dropped tokens than `rules2` |
| `has_mistakes: Bool` first in the schema | Answered "no mistakes" for 97% of drafts with mistakes |
| Gate: keep the draft when the mistakes list is empty | 100% unchanged-when-correct but 28–50% of drafts with mistakes unfixed; unnecessary once the list is in the schema |
| `lines` schema (one entry per line) | Keeps layout, but the model merges lines anyway: 15–18 fallbacks |
| Temperature 0.0 vs 0.2 | No clear difference; 0.2 kept |

## Token budget

From `tokens.py`:

- Instructions (`v1`, with placeholder rule): 323 tokens. `mistakes` schema: 132 tokens. Fixed cost per request: 455 tokens.
- Golden inputs average 1.41 tokens per word (placeholders are cheap; max 4.0 on token-dense rows).
- The output is about as long as the input (up to +60%) and shares the context, so the input budget at 70% of 8,192 is (5,734 − 455) / 2.6 ≈ **2,030 tokens ≈ 1,400 words** before chunking. Phase 2 must read `contextSize` at runtime and derive this, not hard-code it.

## Known issues for Phase 2

- **Multi-line drafts:** the model sometimes merges lines (5–7 rows per run fall back, mostly lists and blockquotes). Rewriting per paragraph (the chunker's paragraph split) should fix both these and the partial edits in long posts.
- **`long-004`** hits `ExceededContextWindowSizeError` in every run, although it's only 244 words. Probably a looping generation under the response cap. Investigate in the Swift harness.
- **Under-correction** (see Judge pass): candidates for v2 are a second "anything left to fix?" pass on short drafts, or sentence-level few-shot examples for comma splices and capitalization.
- **Mentions:** the plain-text heuristic is in `protect.py`. The pasteboard spike (`inspect_pasteboard.swift`) still needs a run against a real Slack draft.

## Reproduce

```bash
uv run --project eval python eval/test_protect.py
uv run --project eval python eval/run.py --variants rules2 --schema mistakes
uv run --project eval python eval/tokens.py
uv run --project eval python eval/judge_sample.py eval/runs/<run>.parquet
```
