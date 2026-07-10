"""Section 3: the cleanup passes and the pluggable pipeline."""

import json

from wordflow.cleanup.doc import CleanupDoc, Segment
from wordflow.cleanup.pipeline import Pipeline, default_pipeline
from wordflow.cleanup.stages import (
    BritishStage, CleanupContext, DictionaryStage, EmDashStage, FillerStage,
    PunctuationStage, default_stages,
)
from wordflow.dictionary.apply import DictEntry


def _ctx(fillers=None, entries=None):
    return CleanupContext(fillers=fillers or [], dict_entries=entries or [])


DEFAULT_FILLERS = ["um", "uh", "er", "erm", "uhm", "you know"]


def test_ac_3_1_a_fillers_removed(fixtures_dir):
    cases = json.loads((fixtures_dir / "cleanup" / "cleanup_cases.json").read_text())
    pipe = Pipeline(default_stages(), {"british": False})  # isolate filler+punctuation
    for case in cases["filler"]:
        result = pipe.run(case["raw"], _ctx(fillers=DEFAULT_FILLERS))
        assert result.text == case["expected"], case


def test_ac_3_1_b_fillers_kept_when_toggled_off():
    pipe = Pipeline(default_stages(), {"filler": False, "british": False})
    result = pipe.run("the plan is um ready", _ctx(fillers=DEFAULT_FILLERS))
    assert "um" in result.text


def test_ac_3_1_c_editable_filler_list():
    # A word not in the list is left alone; adding it makes it strip.
    doc_kept = FillerStage().apply(CleanupDoc.of("this is basically fine"), _ctx(fillers=["um"]))
    assert "basically" in doc_kept.text
    doc_stripped = FillerStage().apply(
        CleanupDoc.of("this is basically fine"), _ctx(fillers=["basically"]))
    assert "basically" not in doc_stripped.text


def test_ac_3_2_a_american_to_british(fixtures_dir):
    cases = json.loads((fixtures_dir / "cleanup" / "cleanup_cases.json").read_text())
    pipe = default_pipeline()
    for case in cases["american"]:
        result = pipe.run(case["raw"], _ctx())
        assert result.text == case["expected"], case


def test_ac_3_2_b_hunspell_flag_matches_polenta_behaviour():
    # Same code path as Polenta's language flag: unknown lowercase words are
    # reported, names and allowlisted terms are not.
    doc = BritishStage().apply(CleanupDoc.of("the zorbleflux from Ben used embeddings"), _ctx())
    assert "zorbleflux" in doc.flags
    assert "Ben" not in doc.flags  # a likely name
    assert "embeddings" not in doc.flags  # in the bundled technical allowlist


def test_ac_3_3_a_em_dash_stripped(fixtures_dir):
    cases = json.loads((fixtures_dir / "cleanup" / "cleanup_cases.json").read_text())
    pipe = default_pipeline()
    for case in cases["emdash"]:
        result = pipe.run(case["raw"], _ctx())
        assert result.text == case["expected"], case
        assert "—" not in result.text


def test_ac_3_4_a_per_stage_toggles_respected():
    raw = "the color is um nice"
    both_off = Pipeline(default_stages(), {"filler": False, "british": False}).run(raw, _ctx(fillers=DEFAULT_FILLERS))
    assert "color" in both_off.text and "um" in both_off.text
    both_on = Pipeline(default_stages(), {}).run(raw, _ctx(fillers=DEFAULT_FILLERS))
    assert "colour" in both_on.text and "um" not in both_on.text


def test_ac_3_5_a_and_b_order_and_protection(fixtures_dir):
    trap = json.loads((fixtures_dir / "cleanup" / "cleanup_cases.json").read_text())["order_trap"]
    entries = [DictEntry(canonical=e["canonical"], hints=e["hints"]) for e in trap["dictionary"]]
    result = default_pipeline().run(trap["raw"], _ctx(entries=entries))
    # Dictionary ran before British and protected "Center Parcs", so the
    # British pass did not rewrite Center -> Centre.
    assert result.text == trap["expected"]
    assert "Centre" not in result.text


def test_ac_3_6_a_dummy_stage_applied_in_order():
    class Shout:
        key = "shout"

        def apply(self, doc, ctx):
            return doc.map_plain(str.upper)

    stages = default_stages()
    stages.insert(2, Shout())  # arbitrary position, between filler and dictionary
    result = Pipeline(stages, {}).run("hello there", _ctx())
    assert "HELLO THERE" in result.text
    assert "shout" not in {s.key for s in default_stages()}  # existing set unchanged


def test_ac_3_6_b_failing_stage_skipped_pipeline_continues():
    class Boom:
        key = "boom"

        def apply(self, doc, ctx):
            raise RuntimeError("stage unavailable, like LM Studio being down")

    stages = default_stages()
    stages.insert(0, Boom())
    result = Pipeline(stages, {}).run("the color", _ctx())
    # The failing stage was skipped; the rest of the pipeline still ran.
    assert result.text == "The colour"
    assert "boom" not in result.applied
    assert "british" in result.applied
