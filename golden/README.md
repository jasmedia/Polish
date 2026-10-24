# Golden set

Test messages shared by the Python evaluation (`eval/`) and the Swift harness (`PolishCore`).
One JSON object per line in `golden.jsonl`.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable id, e.g. `typo-001` |
| `input` | string | The draft as typed |
| `expected` | string | The rewrite Polish should produce, ChatGPT-style: clear, professional English with rephrasing, expanded shorthand and paragraph splits allowed. For messages that are already clear and correct, identical to `input` |
| `tags` | string[] | Any of: `typo`, `homophone`, `article`, `tense`, `agreement`, `run-on`, `rewrite`, `correct`, `slack-syntax`, `long`, `reference` (a real draft and its ChatGPT rewrite, anonymized) |

Target mix (Phase 1): 120 rows with mistakes, 40 correct, 40 Slack-syntax stress cases, 10 long.
Use US English spelling in `expected`. Slack tokens (`<@U123>`, `#channel`, `:emoji:`, URLs, code) must appear in `expected` exactly as in `input`.

**Privacy:** this repo is public. Rows built from real messages must be anonymized before committing: replace people's names, company and product names, links and anything internal, but keep the mistakes and the structure.
