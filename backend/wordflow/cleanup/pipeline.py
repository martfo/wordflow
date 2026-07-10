"""The cleanup pipeline: an ordered list of stages behind one interface, each
individually toggleable. A stage that fails or is unavailable is skipped with a
logged warning and the rest still runs (AC-3.6-b). This is the seam the future
LLM stage plugs into: register it at any position and it applies in order with
no change to the existing stages (AC-3.6-a)."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from wordflow.cleanup.doc import CleanupDoc
from wordflow.cleanup.stages import CleanupContext, CleanupStage, default_stages

log = logging.getLogger("wordflow")


@dataclass
class CleanupResult:
    text: str
    raw: str
    flags: list[str] = field(default_factory=list)
    applied: list[str] = field(default_factory=list)


class Pipeline:
    def __init__(self, stages: list[CleanupStage], toggles: dict[str, bool] | None = None):
        self.stages = stages
        self.toggles = toggles or {}

    def run(self, raw: str, ctx: CleanupContext) -> CleanupResult:
        doc = CleanupDoc.of(raw)
        applied: list[str] = []
        for stage in self.stages:
            if not self.toggles.get(stage.key, True):
                continue
            try:
                doc = stage.apply(doc, ctx)
                applied.append(stage.key)
            except Exception as exc:  # graceful degradation (AC-3.6-b)
                log.warning("cleanup stage %r was skipped: %s", stage.key, exc)
        return CleanupResult(text=doc.text, raw=raw, flags=doc.flags, applied=applied)


def default_pipeline(toggles: dict[str, bool] | None = None) -> Pipeline:
    return Pipeline(default_stages(), toggles)
