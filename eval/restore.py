"""Check and restore ⟦Tn⟧ placeholders, and match the draft's quote style.

Prototype of PolishCore's Validator (placeholder part) and Restore step.
"""

import re
from collections import Counter

from protect import PLACEHOLDER, Protected

CURLY = re.compile("[‘’“”]")


def placeholder_problems(output: str, protected: Protected) -> list[str]:
    """Empty when every placeholder appears exactly once and no unknown ones appear."""
    counts = Counter(int(n) for n in PLACEHOLDER.findall(output))
    problems = []
    for n in range(1, len(protected.tokens) + 1):
        if counts[n] == 0:
            problems.append(f"missing ⟦T{n}⟧")
        elif counts[n] > 1:
            problems.append(f"duplicated ⟦T{n}⟧")
    problems += [f"unknown ⟦T{n}⟧" for n in counts if not 1 <= n <= len(protected.tokens)]
    # A model that rewrites ⟦T1⟧ as [T1] or T1 has broken the token even if the count is right.
    mangled = re.compile(r"[⟦⟧]|\bT\d+\b")
    if len(mangled.findall(PLACEHOLDER.sub("", output))) > len(mangled.findall(PLACEHOLDER.sub("", protected.text))):
        problems.append("mangled placeholder")
    return problems


def restore(output: str, protected: Protected) -> str:
    return PLACEHOLDER.sub(lambda m: protected.tokens[int(m.group(1)) - 1], output)


def uses_curly(text: str) -> bool:
    return CURLY.search(text) is not None


def to_straight(text: str) -> str:
    return text.translate(str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"'}))


def to_curly(text: str) -> str:
    text = re.sub(r"(?<=\w)'|'(?=\d)", "’", text)  # contractions, possessives, '90s
    text = re.sub(r"(^|[\s(\[{])'", "\\1‘", text, flags=re.MULTILINE)
    text = text.replace("'", "’")
    text = re.sub(r'(^|[\s(\[{])"', "\\1“", text, flags=re.MULTILINE)
    return text.replace('"', "”")


def match_quote_style(output: str, source: str) -> str:
    """Convert quotes in protected `output` to the style of protected `source`.

    Run on placeholder text so code and links, which are placeholders, keep their quotes.
    """
    return to_curly(output) if uses_curly(source) else to_straight(output)


_CONTRACTIONS = {
    "i'm": "i am", "i'll": "i will", "i've": "i have", "i'd": "i would", "you're": "you are",
    "you'll": "you will", "we're": "we are", "we'll": "we will", "we've": "we have", "they're": "they are",
    "it's": "it is", "it'll": "it will", "that's": "that is", "there's": "there is", "here's": "here is",
    "what's": "what is", "let's": "let us", "don't": "do not", "doesn't": "does not", "didn't": "did not",
    "isn't": "is not", "aren't": "are not", "wasn't": "was not", "weren't": "were not", "can't": "cannot",
    "won't": "will not", "haven't": "have not", "hasn't": "has not", "wouldn't": "would not",
    "couldn't": "could not", "shouldn't": "should not",
}
# Common work words the writer chose; the model likes to expand them.
_KEPT_TERMS = {"doc": "document", "docs": "documentation", "config": "configuration", "repo": "repository"}


def _match_case(original: str, matched: str) -> str:
    """`original` with the first letter cased like `matched` (the pronoun I stays capital)."""
    if matched[:1].isupper() or original.lower().startswith(("i'", "i’")):
        return original[0].upper() + original[1:]
    return original[0].lower() + original[1:]


def keep_writer_style(output: str, source: str) -> str:
    """Undo expansions of contractions and work words that the draft used and the output dropped."""
    for short, long in list(_CONTRACTIONS.items()) + list(_KEPT_TERMS.items()):
        pattern = short.replace("'", "['’]")
        found = re.search(rf"\b{pattern}\b", source, re.IGNORECASE)
        if found and not re.search(rf"\b{pattern}\b", output, re.IGNORECASE):
            output = re.sub(rf"\b{long}\b", lambda m: _match_case(found.group(), m.group()), output, flags=re.IGNORECASE)
    return output


def keep_layout(output: str, source: str) -> str:
    """Put the rewrite's lines into the draft's layout (blank lines, single breaks) when the counts match.

    The model sometimes collapses a blank line or moves a break; line breaks are Slack syntax (FR-4).
    """
    layout = source.split("\n")
    filled = [i for i, line in enumerate(layout) if line.strip()]
    lines = [line.strip() for line in output.split("\n") if line.strip()]
    if len(lines) != len(filled):
        return output
    for i, line in zip(filled, lines):
        indent = layout[i][: len(layout[i]) - len(layout[i].lstrip())]
        layout[i] = indent + line
    return "\n".join(layout)
