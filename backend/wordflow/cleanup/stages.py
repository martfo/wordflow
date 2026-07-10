"""The cleanup stages, each behind one interface (transcript in, transcript
out) with a stable key used for its Settings toggle. The pinned order is
punctuation, filler, dictionary, British, em dash (AC-3.5-a). The dictionary
stage marks its output protected so the British stage cannot rewrite it
(AC-3.5-b)."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Protocol

from wordflow.cleanup.doc import CleanupDoc, Segment
from wordflow.dictionary.apply import DictEntry, apply_dictionary
from wordflow.language.british import convert_to_british
from wordflow.language.emdash import strip_em_dashes
from wordflow.language.flag import flag_unknown_words


@dataclass
class CleanupContext:
    fillers: list[str] = field(default_factory=list)
    dict_entries: list[DictEntry] = field(default_factory=list)


class CleanupStage(Protocol):
    key: str

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc: ...


class PunctuationStage:
    """Light normalisation of the model's already-punctuated output: collapse
    whitespace, trim, and capitalise the first letter. Never rewrites words."""

    key = "punctuation"

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc:
        def normalise(text: str) -> str:
            text = re.sub(r"\s+", " ", text).strip()
            if text and text[0].isalpha() and text[0].islower():
                text = text[0].upper() + text[1:]
            return text

        return doc.map_plain(normalise)


class FillerStage:
    """Strip the conservative, editable filler list, keeping sentence structure
    intact. 'you know' is removed only as a standalone interjection."""

    key = "filler"

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc:
        fillers = [f for f in ctx.fillers if f.strip()]
        if not fillers:
            return doc
        # Longest first so multi-word fillers win over their first word.
        alternation = "|".join(re.escape(f) for f in sorted(fillers, key=len, reverse=True))
        pattern = re.compile(rf"(?<!\w)(?:{alternation})(?!\w)", re.IGNORECASE)

        def strip(text: str) -> str:
            text = pattern.sub("", text)
            text = re.sub(r"\s+([,.;:!?])", r"\1", text)         # no space before punctuation
            text = re.sub(r"([,;:])(\s*[,;:])+", r"\1", text)    # collapse punctuation runs
            text = re.sub(r"(^|[.!?]\s*)[,;:]+\s*", r"\1", text)  # drop orphan punctuation at a start
            text = re.sub(r"\s{2,}", " ", text)
            text = re.sub(r"^[\s,;:]+", "", text)
            return text.strip()

        return doc.map_plain(strip)


class DictionaryStage:
    """Apply the personal dictionary, marking each replacement protected so no
    later stage rewrites it (AC-3.5-b)."""

    key = "dictionary"

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc:
        if not ctx.dict_entries:
            return doc
        out: list[Segment] = []
        for seg in doc.segments:
            if seg.protected:
                out.append(seg)
            else:
                out.extend(apply_dictionary(seg.text, ctx.dict_entries))
        return CleanupDoc(out, list(doc.flags))


class BritishStage:
    """The American-to-British conversion over plain segments only, plus the
    read-only Hunspell flag. Protected dictionary output is skipped."""

    key = "british"

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc:
        converted = doc.map_plain(convert_to_british)
        allow = {e.canonical for e in ctx.dict_entries}
        plain_text = "".join(s.text for s in converted.segments if not s.protected)
        flags = flag_unknown_words(plain_text, allowlist=allow)
        return CleanupDoc(converted.segments, flags)


class EmDashStage:
    """Strip em dashes last, matching Polenta's convention (AC-3.3)."""

    key = "emdash"

    def apply(self, doc: CleanupDoc, ctx: CleanupContext) -> CleanupDoc:
        return doc.map_plain(strip_em_dashes)


def default_stages() -> list[CleanupStage]:
    """The five stages in the pinned PRD order."""
    return [PunctuationStage(), FillerStage(), DictionaryStage(), BritishStage(), EmDashStage()]
