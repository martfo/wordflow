"""Word error rate: the edit distance between the reference words and the
model's words, divided by the number of reference words. Case and punctuation
are ignored, since the models punctuate and the cleanup pipeline handles
casing; what the harness measures is words heard right (AC-9.5)."""

from __future__ import annotations

import re
from dataclasses import dataclass

_WORD = re.compile(r"[a-z0-9']+")


def normalise(text: str) -> list[str]:
    return _WORD.findall(text.lower())


@dataclass
class WERResult:
    wer: float
    reference_words: int
    substitutions: int
    deletions: int
    insertions: int


def _edit_counts(ref: list[str], hyp: list[str]) -> tuple[int, int, int]:
    """Levenshtein over word tokens, returning (substitutions, deletions,
    insertions) on the optimal alignment."""
    n, m = len(ref), len(hyp)
    # cost[i][j] = edit distance between ref[:i] and hyp[:j]; backtrace for ops.
    cost = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        cost[i][0] = i
    for j in range(m + 1):
        cost[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                cost[i][j] = cost[i - 1][j - 1]
            else:
                cost[i][j] = 1 + min(cost[i - 1][j - 1], cost[i - 1][j], cost[i][j - 1])
    # Backtrace to classify.
    i, j = n, m
    sub = dele = ins = 0
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1] and cost[i][j] == cost[i - 1][j - 1]:
            i, j = i - 1, j - 1
        elif i > 0 and j > 0 and cost[i][j] == cost[i - 1][j - 1] + 1:
            sub += 1; i, j = i - 1, j - 1
        elif i > 0 and cost[i][j] == cost[i - 1][j] + 1:
            dele += 1; i -= 1
        else:
            ins += 1; j -= 1
    return sub, dele, ins


def word_error_rate(reference: str, hypothesis: str) -> WERResult:
    ref = normalise(reference)
    hyp = normalise(hypothesis)
    if not ref:
        # No reference words: a perfect score only if the hypothesis is empty too.
        return WERResult(0.0 if not hyp else 1.0, 0, 0, 0, len(hyp))
    sub, dele, ins = _edit_counts(ref, hyp)
    return WERResult((sub + dele + ins) / len(ref), len(ref), sub, dele, ins)
