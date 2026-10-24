# eval

Prompt evaluation for Polish (Phase 1 of the build plan), using Apple's [Foundation Models SDK for Python](https://github.com/apple/python-apple-fm-sdk).

```bash
uv sync --project eval                                  # needs macOS 26+, Xcode, Apple Intelligence on
uv run --project eval python eval/check_model.py        # smoke test
uv run --project eval jupyter lab                       # notebooks
```

## Files

| File | What it does |
| --- | --- |
| `protect.py` / `restore.py` | Slack-token placeholder prototype (`⟦Tn⟧`), placeholder checks, quote-style matching |
| `test_protect.py` | Token cases + byte-for-byte round trip of every golden row: `uv run --project eval python eval/test_protect.py` |
| `variants/*.txt` | Prompt candidates (`minimal`, `rules`, `fewshot`); the winner is frozen as `prompts/v1.txt` |
| `schemas/` | `fm` CLI schema files for hand tests: `fm respond -i "$(cat prompts/v1.txt)" --schema eval/schemas/RewriteTextOnly.json "…"` |
| `run.py` | Every golden row × variant through the pipeline (protect → generate → validate → retry at 0 → restore); writes `runs/<timestamp>-<schema>-<guardrails>.parquet` (git-ignored) |
| `metrics.py` | Placeholder integrity, unchanged-when-correct, WER vs expected, length ratio, errors, latency |
| `tokens.py` | Token cost of instructions, schema and inputs; chunking budget |
| `analysis.ipynb` | Charts per variant and per tag, failure tables |
| `inspect_pasteboard.swift` | Mention spike: prints what Slack puts on the clipboard (`swift eval/inspect_pasteboard.swift`, then ⌘C in Slack) |
| `compare.py` | Scores Swift harness runs (`make eval-swift`) next to Python runs with `metrics.py`; Phase 2 parity check |
| `tones.py` | Scores `polish-cli golden --tone` runs per tone against the Keep run (change vs keep, length, contractions) |
| `RESULTS.md` | Scores of the prompt that ships |

```bash
uv run --project eval python eval/run.py                          # all variants, text schema
uv run --project eval python eval/run.py --variants rules --schema changes --guardrails permissive
```
