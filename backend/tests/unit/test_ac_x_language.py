"""Cross-cutting: the British English pass (ported from Polenta) and the
source-string lint (AC-8.5)."""

import json

from wordflow.language.british import MAP_PATH, convert_to_british
from wordflow.language.flag import flag_unknown_words
from wordflow.language.lint import lint_repo, lint_text


def test_source_string_lint(repo_root):
    """No em dashes and no denylisted American spellings in app-authored
    strings. Positive control first, then the repository itself is clean."""
    bad = "We organized the color scheme — nicely."
    problems = {v.problem for v in lint_text(bad, "control")}
    assert "em dash" in problems
    assert any("organized" in p for p in problems)
    assert any("color" in p for p in problems)

    violations = lint_repo(repo_root)
    assert violations == [], "\n".join(str(v) for v in violations)


def test_british_conversion():
    text = (
        "The color scheme will organize the report for Denver Analytics. "
        "Run `organize_files(color)` to check. The kohlrabi is unaffected."
    )
    converted = convert_to_british(text)
    assert "colour scheme" in converted
    assert "organise the report" in converted
    assert "Denver Analytics" in converted
    assert "`organize_files(color)`" in converted  # code spans left alone
    assert "kohlrabi" in converted
    assert convert_to_british("Color and COLOR") == "Colour and COLOUR"


def test_dictionary_flagging():
    text = "The zorbleflux reading came from Ben Adams. Call `weirdfn()` and check kubernetes."
    flags = flag_unknown_words(text, allowlist={"kubernetes"})
    assert flags == ["zorbleflux"]


def test_map_contents():
    mapping = json.loads(MAP_PATH.read_text())
    assert mapping["color"] == "colour"
    assert mapping["organize"] == "organise"
    assert mapping["analyze"] == "analyse"
    assert mapping["center"] == "centre"
    for excluded in ("license", "practice", "program"):
        assert excluded not in mapping
