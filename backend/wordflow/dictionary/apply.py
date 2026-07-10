"""Applying the personal dictionary to a transcript.

Two kinds of match, both producing the entry's canonical form as a protected
segment (AC-5.1):

- sounds-like hints: a hint phrase heard in the transcript is replaced with the
  canonical spelling ("melly pap" -> "mieliepap").
- near-miss of the canonical itself, defined exactly as case differences or
  hyphen/space/punctuation variants of the entry ("mielie pap", "Mieliepap" ->
  "mieliepap"). Anything fuzzier needs a hint.

Both are matched over windows of consecutive word tokens joined only by
in-word separators (space, hyphen, underscore, dot, apostrophe), compared by a
separator-and-case-insensitive normal form, so a comma or sentence break never
bridges a window.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from wordflow.cleanup.doc import Segment

_TOKEN = re.compile(r"[A-Za-z0-9]+")
_JOINER = re.compile(r"^[\s\-_.']*$")
_MAX_WINDOW = 6


@dataclass
class DictEntry:
    canonical: str
    hints: list[str] = field(default_factory=list)
    enabled: bool = True


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


@dataclass
class _Target:
    norm: str
    canonical: str
    words: int  # word-token count of the match target, an upper bound on the window


def _targets(entries: list[DictEntry]) -> list[_Target]:
    targets: list[_Target] = []
    for entry in entries:
        if not entry.enabled:
            continue
        for phrase in [entry.canonical, *entry.hints]:
            norm = _norm(phrase)
            if not norm:
                continue
            targets.append(_Target(norm, entry.canonical, len(_TOKEN.findall(phrase)) or 1))
    # Longer normal forms first, so a specific multi-word entry wins over a
    # shorter one that is a prefix of it.
    targets.sort(key=lambda t: len(t.norm), reverse=True)
    return targets


def apply_dictionary(text: str, entries: list[DictEntry]) -> list[Segment]:
    """Return the transcript as segments: plain runs interleaved with protected
    canonical replacements. When no entry matches, one plain segment."""
    targets = _targets(entries)
    if not targets:
        return [Segment(text, protected=False)]

    tokens = list(_TOKEN.finditer(text))
    segments: list[Segment] = []
    plain_start = 0  # start of the pending plain run in `text`
    i = 0
    while i < len(tokens):
        match = _match_at(text, tokens, i, targets)
        if match is None:
            i += 1
            continue
        canonical, end_token = match
        span_start = tokens[i].start()
        span_end = tokens[end_token].end()
        # Flush the plain text before this match.
        if span_start > plain_start:
            segments.append(Segment(text[plain_start:span_start], protected=False))
        segments.append(Segment(canonical, protected=True))
        plain_start = span_end
        i = end_token + 1

    if plain_start < len(text):
        segments.append(Segment(text[plain_start:], protected=False))
    return segments or [Segment(text, protected=False)]


def _match_at(
    text: str, tokens: list[re.Match[str]], i: int, targets: list[_Target]
) -> tuple[str, int] | None:
    """The best (longest) canonical match starting at token i, or None. Returns
    (canonical, last-token-index)."""
    # Longest window first so a two-word entry beats a one-word prefix.
    max_k = min(_MAX_WINDOW, len(tokens) - i)
    for k in range(max_k, 0, -1):
        end = i + k - 1
        if not _window_is_joined(text, tokens, i, end):
            continue
        window_norm = _norm("".join(text[tokens[j].start():tokens[j].end()] for j in range(i, end + 1)))
        for target in targets:
            if target.norm == window_norm and k <= target.words + 1:
                matched_text = text[tokens[i].start():tokens[end].end()]
                # Protect even an exact hit so a later pass cannot rewrite it;
                # only skip when it is already exactly canonical AND there is
                # nothing to protect it from would be premature, so always keep.
                return target.canonical, end
    return None


def _window_is_joined(text: str, tokens: list[re.Match[str]], start: int, end: int) -> bool:
    """True when every gap between the tokens start..end is only in-word
    separators, so the window is a single hyphen/space/punctuation variant and
    not a phrase spanning a comma or sentence break."""
    for j in range(start, end):
        gap = text[tokens[j].end():tokens[j + 1].start()]
        if not _JOINER.match(gap):
            return False
    return True
