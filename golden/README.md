# Golden set

Test messages shared by the Python evaluation (`eval/`) and the Swift harness (`PolishCore`).
One JSON object per line in `golden.jsonl`.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable id, e.g. `typo-001` |
| `input` | string | The draft as typed |
| `expected` | string | The correct rewrite. For already-correct messages, identical to `input` |
| `tags` | string[] | Any of: `typo`, `homophone`, `article`, `tense`, `agreement`, `run-on`, `correct`, `slack-syntax`, `long` |

Target mix (Phase 1): 120 rows with mistakes, 40 correct, 40 Slack-syntax stress cases, 10 long.
Use US English spelling in `expected`. Slack tokens (`<@U123>`, `#channel`, `:emoji:`, URLs, code) must appear in `expected` exactly as in `input`.
