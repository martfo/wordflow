"""Learning from corrections: when the user edits a history entry and the change
is a small, anchored word-level fix, the app offers "Always transcribe X as Y?"
and, if accepted, a dictionary entry is created (AC-5.2).

The changed span is found by trimming the common prefix and suffix of the two
word lists, so a multi-word mishearing collapsing to one word ("melly pap" ->
"mieliepap") is caught as readily as a single-word swap. A change with no
surrounding context in common, or one that is too large, is treated as a full
rewrite and offered nothing."""

from __future__ import annotations

import re
from dataclasses import dataclass

_EDGE_PUNCT = re.compile(r"^\W+|\W+$")
_MAX_SPAN_WORDS = 4


def _strip(phrase: str) -> str:
    return _EDGE_PUNCT.sub("", phrase).strip()


@dataclass
class WordChange:
    heard: str      # what the model produced (becomes the sounds-like hint)
    corrected: str  # what the user wants instead (becomes the canonical)


def single_word_change(old: str, new: str) -> WordChange | None:
    old_words = old.split()
    new_words = new.split()

    # Trim the common prefix and suffix.
    start = 0
    while start < len(old_words) and start < len(new_words) and old_words[start] == new_words[start]:
        start += 1
    end_old, end_new = len(old_words), len(new_words)
    while end_old > start and end_new > start and old_words[end_old - 1] == new_words[end_new - 1]:
        end_old -= 1
        end_new -= 1

    old_mid = old_words[start:end_old]
    new_mid = new_words[start:end_new]
    if not old_mid or not new_mid:
        return None  # a pure insertion or deletion, not a substitution
    if start == 0 and end_old == len(old_words) and end_new == len(new_words):
        return None  # nothing in common: a full rewrite, not a word-level fix
    if len(old_mid) > _MAX_SPAN_WORDS or len(new_mid) > _MAX_SPAN_WORDS:
        return None

    heard = _strip(" ".join(old_mid))
    corrected = _strip(" ".join(new_mid))
    if not heard or not corrected or heard.lower() == corrected.lower():
        return None
    return WordChange(heard=heard, corrected=corrected)
