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

# Phase 2 results: Swift pipeline (PolishCore)

`polish-cli golden` (release build) runs the same prompt, schema and temperature through `Pipeline`, and `compare.py` scores it with `metrics.py`. Both pipelines use the keep-at-start rule for any leading placeholder (added in this phase, see below). Python run C is a re-run of `run.py` with that rule; runs A and B are from Phase 1. Scored 2026-10-24.

| Metric | Python A | Python B | Python C | Swift 1 | Swift 2 | Phase 1 target |
| --- | --- | --- | --- | --- | --- | --- |
| Placeholder integrity, first attempt | 100% | 100% | 100% | 100% | 98.8% | ≥ 99% |
| Placeholder integrity, after retry | 100% | 100% | 100% | 100% | 100% | |
| Unchanged when correct | 97.9% | 97.9% | 100% | 95.8% | 95.8% | ≥ 95% |
| p90 latency, inputs ≤ 60 words | 1.85 s | 1.78 s | 2.28 s | 1.71 s | 2.18 s | ≤ 3 s |
| WER vs `expected`, rows with mistakes | 0.245 | 0.253 | 0.239 | 0.221 | 0.226 | |
| Exact match, rows with mistakes | 8.6% | 5.6% | 9.9% | 14.2% | 14.2% | |
| Rows with mistakes left unchanged | 10.5% | 8.0% | 8.6% | 5.6% | 6.2% | |
| Fallbacks | 6 | 7 | 6 | 6 | 6 | |
| Generation errors | 1 | 1 | 1 | 0 | 0 | |

**Parity is not within 1 point on every metric.** With the same instructions, the Swift framework corrects more (WER −0.02, exact match +4 to 9 points, fewer drafts left unfixed) and is slightly less conservative on correct drafts:

- `correct-017` (`push` → `deploy`) and `correct-021` (`standup` → `the standup`) are edited in both Swift runs and in no Python run. Both look prompt-driven: `deploy` is in the prompt's keep-words list. Candidates for prompt v2.
- `slack-012` dropped both placeholders on the first attempt in Swift run 2; the retry at temperature 0 passed.
- `long-004`, the `ExceededContextWindowSizeError` row in Python, generates normally in Swift (no rechunk needed).

## Investigation of the gaps

The raw outputs show the model listing placeholders as mistakes (`mistakes: ["⟦T1⟧", "push"]` on `correct-017`, `["⟦T1⟧", "⟦T2⟧"]` on the `slack-012` miss) before editing around them. Each row below was run 10 times through the Swift framework at temperature 0.2 (scratch harness, same instructions as the pipeline):

| Row | Current guide | Guide + "⟦Tn⟧ placeholders are never mistakes." |
| --- | --- | --- |
| `correct-017` (`push` → `deploy`) | 4 / 10 ok | 10 / 10 ok |
| `slack-012` (drops both placeholders) | 9 / 10 ok | 10 / 10 ok |
| `apostrophe-003` (`10` → `10 a.m.`) | 10 / 10 ok | 4 / 10 ok |
| `correct-021` (`standup` → `the standup`) | 1 / 10 ok | 1 / 10 ok |
| `slack-019` (code block placeholder) | 9 / 10 ok | 8 / 10 ok |
| Total bad | 17 / 50 | 17 / 50 |

Full re-scores with the guide sentence confirmed the trade: Swift unchanged-when-correct stayed at 95.8% (`apostrophe-003` replaced `correct-017`), and the Python run with it also dropped to 95.8%. **The sentence was reverted**; the schema stays as scored in Phase 1. Also tried and dropped: removing `deploy` from the prompt's keep-words list (no gain over the guide sentence) and adding "do not add words to correct sentences" (no effect on `correct-021`).

Conclusions:

- The 1-point parity target is tighter than run-to-run noise. One row moves unchanged-when-correct by 2.1 points (48 correct rows) and integrity by 1.2 points (86 rows with tokens); Python alone spans 95.8–100% unchanged-when-correct across its four runs.
- The one consistent Swift-only difference is `correct-017`, which the Swift framework edits 6 times in 10 and Python never did. The instructions are byte-identical (checked by `InstructionsTests`), so it comes from the runtime, not the port.
- `correct-021` and `apostrophe-003` are prompt v2 issues (articles and added details on correct drafts), together with under-correction.
- Swift latency in the last two runs (p90 ≤ 60 words 3.2 s and 2.4 s) was measured while other work ran on this Mac (load average 2–3.5); earlier Swift runs measured 1.7–2.2 s. Re-measure on an idle machine in Phase 3's Instruments pass.

## Changes made in this phase

| Change | Effect |
| --- | --- |
| Keep-at-start rule for any leading placeholder (`LEADING_RULE`), not just mentions (`LEADING_MENTION_RULE`) | First Swift runs dropped a leading emoji (`slack-011`) and bold label (`slack-021`) on both attempts: integrity 97.7% → 100% / 98.8% |
| Chunker also splits on end punctuation | NLTokenizer misses sentences that start lowercase; only affects drafts over the token budget (none in the golden set) |

## Reproduce

```bash
make eval-swift
uv run --project eval python eval/compare.py --swift eval/runs/<swift>.jsonl --python eval/runs/<python>.parquet
```

# Phase 4: tones (prompt v2, in progress)

Keep my tone stays on `prompts/v1.txt`. Prompt v2 is a separate restyle template for Casual, Professional and Concise: `prompts/v2.txt` plus one `{tone}` text per tone in `prompts/v2-tones/`. `InstructionsBuilder.Restyle` loads it; the app still uses v1 for every tone. Other tones also skip the writer-style restore, which would undo Professional's written-out contractions. Scored 2026-10-25 on the 210-row golden set through the Swift pipeline (`polish-cli golden --tone T --tone-prompt prompts/v2.txt`), with `eval/tones.py`.

The golden `expected` values are written in the default tone, so the other tones are measured against the Keep run: how far they move from it (`change_vs_keep`, word edit rate) and in which direction.

| Metric | v1 keep | v1 casual | v1 prof. | v1 concise | v2c casual | v2c prof. | v2c concise |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Placeholder integrity, first attempt | 100% | 95.3% | 98.8% | 97.7% | 98.8% | 95.3% | 95.3% |
| Fallbacks (of 210) | 5 | 8 | 8 | 8 | 10 | 13 | 22 |
| Change vs keep (word edit rate) | | 0.06 | 0.06 | 0.04 | 0.16 | 0.20 | 0.24 |
| Contractions per 100 words | 1.47 | 1.72 | 1.33 | 1.39 | 1.50 | 0.22 | 0.32 |
| Length ratio, inputs ≥ 20 words | 1.05 | 1.04 | 1.05 | 1.04 | 1.04 | 1.06 | 0.96 |
| Rows ≥ 10% shorter than keep | | 2% | 1% | 1% | 4% | 4% | 31% |
| Correct rows changed | 6% | 8% | 8% | 6% | 31% | 67% | 63% |
| p90 latency, inputs ≤ 60 words | 1.71 s | 1.74 s | 2.26 s | 2.22 s | 1.87 s | 2.00 s | 2.14 s |

**v1 tones are cosmetic:** each moves 4–6% of words from Keep, about run-to-run noise. v2 makes Professional clearly different (contractions down 85%), Casual somewhat, and Concise shorter on a third of rows.

**Meaning check** (15 changed rows per tone, seed 7, read in the development session):

| Tone | v2b | v2c | v2c failures |
| --- | --- | --- | --- |
| Casual | 12 / 15 | 15 / 15 | None; one added "Hey, just a quick", and 6 of 15 leave lowercase sentence starts |
| Professional | 15 / 15 | 13 / 15 | "or merge it know?" → "or merge it, can you decide?"; `eod` → "end of week" |
| Concise | 11 / 15 | 12 / 15 | "i am thinking we take…" → "we take…" (proposal became decision); "Feel free to add topics" → "Can you add topics"; "can someone pick it up" → "Can you take them up?" |

**Placeholders guard meaning.** In Professional, "please *do not* restart the worker nodes" came back as "could you restart the worker nodes": the model dropped the bold span and flipped the instruction. Validation caught the missing placeholder and kept the original. The other placeholder drops are code blocks merged away with their lines (`slack-019`, `slack-034`).

**Not shippable yet.** Open problems, in order:

1. **Meaning changes** in Concise (and two in Professional): requests, offers and proposals change kind. Every one breaks the "meaning never changes" rule.
2. **Merged lines** cause most fallbacks (10–20 per tone; v1 keep has 5), and take code-block placeholders with them. The "keep every line" rule doesn't help. Next: restyle multi-line drafts one paragraph (or list item) at a time.
3. **Placeholder integrity** is 95.3% for Professional and Concise, below the 99% bar; mostly the same merged code blocks.
4. **Under-correction** in Casual (lowercase starts kept), the same weakness as v1.

| Draft | Change | Result |
| --- | --- | --- |
| v2a | v1's rules minus "leave correct sentences alone", tone line at the end | Professional stiff and long (18 length fallbacks: "Please determine whether…"), "merge" → "deploy" from the keep-words list |
| v2b | Tone first; technical terms kept as written; no added requests or nicknames; questions stay questions; Professional "clear, not formal" | Professional fallbacks 26 → 13, length rejects 18 → 2; Casual and Concise flip requests ("please let me know your availability" → "I'll let you know my availability") |
| v2c | "The writer is sending it to colleagues, not to you: never answer it"; who-does-what rule; no "I'll" or "write I as a capital" in Casual (both primed sentences starting with "I"); Concise "fewer words, not a blunter message" | Casual meaning 12 → 15 of 15 and fallbacks 16 → 10; Concise less aggressive (51% → 31% of rows shorter) with fewer flips |
| Two-stage (tried on 20 dev rows) | Polish in Keep first, then restyle the corrected text | Same flips, some invented sentences ("Can you respond?"), +1.2 s per message. Dropped |

## Line by line (v2c-lines)

The restyle tones send each non-blank line to the model on its own (`Chunker.lines`); lines with no words outside placeholders (a code block, an emoji, a link) are kept as they are. Same v2c prompt.

| Metric | v2c casual | v2c prof. | v2c concise | lines casual | lines prof. | lines concise |
| --- | --- | --- | --- | --- | --- | --- |
| Placeholder integrity, first attempt | 98.8% | 95.3% | 95.3% | 94.2% | 95.3% | 96.5% |
| Fallbacks (of 210) | 10 | 13 | 22 | 17 | 18 | 15 |
| Fallbacks for merged lines | 10 | 10 | 20 | 0 | 0 | 0 |
| Fallbacks for length | 1 | 2 | 2 | 16 | 16 | 14 |
| Long rows (10), median / max latency | | | | 23.8 s / 30.7 s | 24.6 s / 44.2 s | 22.3 s / 37.2 s |

**Merged lines are gone, but the split doesn't ship as is:**

- **Latency:** one call per line makes the 10 long rows take 22–25 s (median), against the ≤ 8 s p90 target for 300 words (FR-12).
- **Short lines alone make things up.** A line like `todo for release:`, `Steps to reproduce:` or `Got it, thanks!` sent alone often comes back with the framework's guided-generation prompt copied in ("Respond using the following JSON format: {…"): 12–14 rows per tone. Length validation caught all but one: `long-008` in Concise shipped with that text in it.
- **Example words become content.** Lists in the prompt (`PR, merge, sheet and repo`, `check, need, fix, works, demo`) turn into invented sentences: "I finished the PR / I also did the merge / I made the sheet", "The demo works as expected". This also happens in single-pass v2c on a few rows that pass validation: "still not able to reproduce" → "…reproduce the PR"; "None of them are blocking" → "None block the merge".

**Changes from this run:**

- New validation failure `leak`: an output containing "Respond using the following" or "JSON format" (when the draft doesn't) is rejected, for every tone including Keep. v1 Professional produced one such raw output before this; validation had caught it on length.

**Next:** rewrite in one call as before, and split by line only when that call fails with merged lines (cost only on those rows); send lines of three words or fewer with the Keep instructions; drop the example word lists from v2.

## Split by line only after a merge (v2d, current)

**Shipped 2026-10-25 for Casual and Professional** (`Prompt.v2`, the default `InstructionsBuilder`). Keep my tone and Concise stay on v1. `polish-cli` without `--tone-prompt` runs what the app ships.

One call per message as before. When a restyle attempt merges lines, the pipeline skips the temperature-0 retry and rewrites the chunk line by line (`Pipeline.rewriteByLine`, `ChunkTrace.splitByLine`): lines without words stay as they are, and lines of three words or fewer get Keep my tone. Prompt v2 loses its example word lists (`PR, merge, sheet and repo`, `check, need, fix, works, demo`, filler and request examples); the shorthand list stays, since it names input forms to expand. Keep my tone is unchanged.

| Metric | v2c casual | v2c prof. | v2c concise | v2d casual | v2d prof. | v2d concise |
| --- | --- | --- | --- | --- | --- | --- |
| Placeholder integrity, first attempt | 98.8% | 95.3% | 95.3% | 97.7% | 97.7% | 96.5% |
| Placeholder integrity, after retry | 98.8% | 95.3% | 95.3% | 98.8% | 98.8% | 98.8% |
| Fallbacks (of 210) | 10 | 13 | 22 | 7 | 14 | 10 |
| Change vs keep (word edit rate) | 0.16 | 0.20 | 0.24 | 0.16 | 0.22 | 0.22 |
| Rows ≥ 10% shorter than keep | 4% | 4% | 31% | 4% | 3% | 21% |
| p90 latency, inputs ≤ 60 words | 1.87 s | 2.00 s | 2.14 s | 1.79 s | 2.10 s | 2.14 s |
| Long rows (10), median latency | 14.3 s | 10.7 s | 16.2 s | 26.7 s | 27.8 s | 30.1 s |
| Outputs with prompt example words not in the draft | 2 | 4 | 6 | 0 | 0 | 0 |
| Meaning kept (15 changed rows, seed 7) | 15 / 15 | 13 / 15 | 12 / 15 | 15 / 15 | 15 / 15 | 12 / 15 |

**Better on safety and fallbacks:** no invented example words, no format-prompt leaks shipped, integrity after retry 98.8% in every tone (0.2 points under the bar; `slack-022`'s dropped `*do not*` is among the misses, and validation keeps the draft), and fallbacks down for Casual and Concise.

**Still open:**

1. **Concise changes meaning** (12 / 15): "can we move the meeting to thursday" → "We can move the meeting…"; "me and Ravi" → "We" (Ravi dropped); "i think the db pool is exhausted" → a flat claim. It also shortens less without the filler list (21% of rows vs 31%).
2. **Long drafts are slow.** 5–6 of the 10 long rows merge lines and take the line-by-line path: median 27–30 s. Keep my tone already takes 8.9 s median on these rows, over the ≤ 8 s p90 target for 300 words (FR-12), so long drafts need either progress UI or fewer calls whatever the tone.
3. **Under-correction** in Casual and Professional (lowercase sentence starts kept on about a quarter of the sampled rows), and one curly → single quote swap in Professional.

```bash
swift run -c release --package-path Packages/PolishCore polish-cli golden --tone casual --tone-prompt prompts/v2.txt
uv run --project eval python eval/tones.py eval/runs/tones-*.jsonl
```
