# Golden set

Test messages shared by the Python evaluation (`eval/`) and the Swift harness (`PolishCore`).
One JSON object per line in `golden.jsonl`.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable id, e.g. `typo-001` |
| `input` | string | The draft as typed |
| `expected` | string | The rewrite Polish should produce, ChatGPT-style: clear, professional English with rephrasing, expanded shorthand and paragraph splits allowed. For messages that are already clear and correct, identical to `input` |
| `tags` | string[] | Any of: `typo`, `homophone`, `article`, `tense`, `agreement`, `run-on`, `rewrite`, `correct`, `slack-syntax`, `long`, `mention` (display-name mentions such as `@Alex Morgan`), `apostrophe` (quote style must be kept exactly), `reference` (a real draft and its ChatGPT rewrite, anonymized) |

Target mix (Phase 1): 120 rows with mistakes, 40 correct, 40 Slack-syntax stress cases, 10 long.
Use US English spelling in `expected`. Slack tokens (`<@U123>`, `#channel`, `:emoji:`, URLs, code) must appear in `expected` exactly as in `input`.

**Mentions:** a display-name mention (`@` plus up to three Title Case words, or `@here` / `@channel` / `@everyone`) must appear in `expected` exactly as in `input`. A lowercase word or a common sentence-start word (`We`, `I`, `Can`, `Please`, `The`…) right after a mention is not part of it: in `@Alex can you…` and `@Sam We can…` only `@Alex` and `@Sam` are protected, and the rest may be rewritten.

**Apostrophes and quotes:** `expected` uses the same style as `input`: straight (`'`, `"`) when the input is straight or has none, curly (`’`, `“ ”`) when the input is curly. Polish converts the model's output to the input's style in code. Scorers treat straight and curly as equal, except on rows tagged `apostrophe`, which must match exactly.

**Privacy:** this repo is public. Rows built from real messages must be anonymized before committing: replace people's names, company and product names, links and anything internal, but keep the mistakes and the structure.
