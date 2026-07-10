"""The source-string lint: a cheap guard on our own user-facing strings,
separate from the dictionary pass on transcribed text. No em dashes and no
common American spellings in app-authored strings. Ported from Polenta and
pointed at WordFlow's sources (AC-8.5)."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

# Common American spellings and their frequent inflections.
DENYLIST = [
    "color", "colors", "colored", "colorful",
    "organize", "organizes", "organized", "organizing", "organization",
    "analyze", "analyzes", "analyzed", "analyzing",
    "center", "centers", "centered",
    "behavior", "behaviors",
    "favorite", "favorites",
    "catalog", "catalogs",
    "defense", "defenses",
    "recognize", "recognizes", "recognized", "recognizing",
    "summarize", "summarizes", "summarized", "summarizing",
    "apologize", "customize", "customized", "initialize", "initialized",
    "flavor", "honor", "labor", "neighbor",
]

_DENY = re.compile(r"\b(" + "|".join(DENYLIST) + r")\b", re.IGNORECASE)
_SWIFT_STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


@dataclass
class LintViolation:
    source: str
    problem: str
    snippet: str

    def __str__(self) -> str:
        return f"{self.source}: {self.problem}: {self.snippet!r}"


def lint_text(text: str, source: str) -> list[LintViolation]:
    violations = []
    for line in text.splitlines():
        if "—" in line:
            violations.append(LintViolation(source, "em dash", line.strip()[:80]))
        for match in _DENY.finditer(line):
            violations.append(
                LintViolation(source, f"American spelling {match.group(0)!r}", line.strip()[:80])
            )
    return violations


def lint_swift_sources(sources_dir: Path) -> list[LintViolation]:
    """Only string literals: identifiers and comments are not user-facing."""
    violations = []
    for path in sorted(sources_dir.rglob("*.swift")):
        for match in _SWIFT_STRING.finditer(path.read_text()):
            violations.extend(lint_text(match.group(1), str(path)))
    return violations


def lint_repo(repo_root: Path) -> list[LintViolation]:
    violations = []
    # The bundled default filler list is user-visible in Settings.
    fillers = repo_root / "backend" / "wordflow" / "resources" / "fillers.txt"
    if fillers.exists():
        violations.extend(lint_text(fillers.read_text(), str(fillers)))
    app_sources = repo_root / "app" / "Sources"
    if app_sources.exists():
        violations.extend(lint_swift_sources(app_sources))
    return violations
