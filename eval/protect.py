"""Replace Slack tokens with ⟦Tn⟧ placeholders so the model never sees raw Slack syntax.

Prototype of PolishCore's Protector. `restore(*protect(text)) == text` for every input.
"""

import re
from dataclasses import dataclass, field

PLACEHOLDER = re.compile(r"⟦T(\d+)⟧")

# Words that start a sentence rather than continue a display name: `@Sam We can…` protects `@Sam`.
_NAME_STOPWORDS = {
    "a", "all", "also", "an", "and", "any", "are", "as", "but", "can", "could", "did", "do", "does",
    "for", "fyi", "good", "great", "has", "have", "here", "hey", "hi", "how", "i", "i'd", "i'll", "i'm",
    "i've", "if", "in", "is", "it", "it's", "its", "just", "kindly", "let", "let's", "my", "nice", "no",
    "not", "ok", "okay", "on", "once", "our", "please", "pls", "quick", "should", "so", "sorry", "sure",
    "thank", "thanks", "that", "the", "there", "these", "this", "we", "what", "when", "where", "who",
    "why", "will", "would", "yes", "you", "your",
}

_NAME_WORD = r"[A-Z][\w'’-]*"

# Order matters: at the same start position the first alternative wins.
_TOKEN = re.compile(
    "|".join([
        r"(?P<codeblock>```.*?```)",                           # fenced code, may span lines
        r"(?P<code>`[^`\n]+`)",                                # inline code
        r"(?P<angle><[@#!][^>\s]*(?:\|[^>]*)?>|<https?://[^>\s]+(?:\|[^>]*)?>)",  # <@U1>, <#C1|x>, <!here>, <url|label>
        r"(?P<url>https?://[^\s<>]*[^\s<>.,;:!?)\]'\"’”])",   # bare URL, minus trailing punctuation
        r"(?P<email>[\w.+-]+@[\w-]+(?:\.[\w-]+)+)",
        r"(?P<emoji>(?::[a-z0-9_+'-]+:)+)",                    # :wave::skin-tone-3: is one token
        r"(?P<broadcast>@(?:here|channel|everyone)\b)",
        r"(?P<mention>@\w[\w'’-]*(?:[ ]" + _NAME_WORD + r"){0,2})",  # trimmed in _trim_mention
        r"(?P<channel>(?<![\w&])#[a-z0-9][a-z0-9_-]*)",
        r"(?P<format>(?<![\w*_~])(?P<mark>~~|[*_~])(?=\S)[^\n]*?(?<=\S)(?P=mark)(?![\w*_~]))",  # *bold*, _italic_, ~strike~ span
    ]),
    re.DOTALL,
)


@dataclass
class Protected:
    text: str
    tokens: list[str] = field(default_factory=list)  # tokens[n - 1] is the original for ⟦Tn⟧


def _trim_mention(token: str) -> str:
    words = token.split(" ")
    kept = [words[0]]
    for word in words[1:]:
        if word.lower().replace("’", "'") in _NAME_STOPWORDS:
            break
        kept.append(word)
    return " ".join(kept)


def _dictionary_pattern(words: list[str]) -> re.Pattern | None:
    if not words:
        return None
    alts = "|".join(re.escape(w) for w in sorted(words, key=len, reverse=True))
    return re.compile(rf"(?<![\w@#])(?:{alts})(?!\w)")


def protect(text: str, dictionary: list[str] | None = None) -> Protected:
    if PLACEHOLDER.search(text):
        raise ValueError("input already contains a ⟦Tn⟧ placeholder")

    spans: list[tuple[int, int]] = []
    pos = 0
    while (m := _TOKEN.search(text, pos)) is not None:
        start, end = m.span()
        kind = m.lastgroup
        if kind == "mention":
            end = start + len(_trim_mention(m.group()))
        spans.append((start, end))
        pos = end

    if (dict_re := _dictionary_pattern(dictionary or [])) is not None:
        for m in dict_re.finditer(text):
            if not any(s < m.end() and m.start() < e for s, e in spans):
                spans.append(m.span())
        spans.sort()

    out, tokens, last = [], [], 0
    for start, end in spans:
        out.append(text[last:start])
        tokens.append(text[start:end])
        out.append(f"⟦T{len(tokens)}⟧")
        last = end
    out.append(text[last:])
    return Protected("".join(out), tokens)
