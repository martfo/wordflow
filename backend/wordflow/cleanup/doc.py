"""The document that flows through the cleanup pipeline.

A CleanupDoc is a sequence of segments, each either plain or protected. A stage
that produces a canonical form (the personal dictionary) marks its output
protected; later stages skip protected segments, so a taught spelling
("Center Parcs") survives the British pass (AC-3.5-b). Whole-text stages use
`map_plain`, which transforms only the plain segments and leaves protected ones
untouched.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable


@dataclass
class Segment:
    text: str
    protected: bool = False


@dataclass
class CleanupDoc:
    segments: list[Segment]
    # Read-only Hunspell flags surfaced by the British pass; never change text.
    flags: list[str] = field(default_factory=list)

    @classmethod
    def of(cls, text: str) -> "CleanupDoc":
        return cls([Segment(text, protected=False)])

    @property
    def text(self) -> str:
        return "".join(s.text for s in self.segments)

    def map_plain(self, fn: Callable[[str], str]) -> "CleanupDoc":
        """Apply `fn` to each plain segment's text; protected segments pass
        through unchanged. Empty results are dropped."""
        out: list[Segment] = []
        for s in self.segments:
            if s.protected:
                out.append(s)
            else:
                out.append(Segment(fn(s.text), protected=False))
        return CleanupDoc([s for s in out if s.text != "" or s.protected], list(self.flags))
