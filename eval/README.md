# eval

Prompt evaluation for Polish (Phase 1 of the build plan), using Apple's [Foundation Models SDK for Python](https://github.com/apple/python-apple-fm-sdk).

```bash
uv sync --project eval                                  # needs macOS 26+, Xcode, Apple Intelligence on
uv run --project eval python eval/check_model.py        # smoke test
uv run --project eval jupyter lab                       # notebooks
```

Coming in Phase 1:

- `protect.py` / `restore.py` — Slack-token placeholder prototype
- `run.py` — runs every golden row through each prompt variant, writes `eval/runs/<timestamp>.parquet`
- `RESULTS.md` — scores of the prompt that ships
