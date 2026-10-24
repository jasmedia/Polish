"""Smoke test: is the on-device model reachable from Python?

Run with: uv run --project eval python eval/check_model.py
"""

import asyncio
import sys

import apple_fm_sdk as fm


async def main() -> int:
    model = fm.SystemLanguageModel()
    is_available, reason = model.is_available()
    if not is_available:
        print(f"Model not available: {reason}")
        return 1

    print(f"Context size: {model.context_size} tokens")
    session = fm.LanguageModelSession(instructions="Reply with one short sentence.")
    response = await session.respond("Say hello.")
    print(f"Model replied: {response}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
