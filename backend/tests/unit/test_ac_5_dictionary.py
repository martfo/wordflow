"""Section 5: the personal dictionary and learning from corrections."""

from wordflow.cleanup.pipeline import default_pipeline
from wordflow.cleanup.stages import CleanupContext
from wordflow.dictionary.apply import DictEntry, apply_dictionary
from wordflow.dictionary.learning import single_word_change
from wordflow.dictionary import store


def _ctx(entries):
    return CleanupContext(dict_entries=entries)


def _text(segments):
    return "".join(s.text for s in segments)


def test_ac_5_1_a_sounds_like_hint():
    entries = [DictEntry(canonical="mieliepap", hints=["melly pap"])]
    segments = apply_dictionary("we ate melly pap for lunch", entries)
    assert _text(segments) == "we ate mieliepap for lunch"
    assert any(s.protected and s.text == "mieliepap" for s in segments)


def test_ac_5_1_b_near_miss_without_hint():
    entries = [DictEntry(canonical="mieliepap")]
    # Case difference and space variant both correct to canonical.
    assert _text(apply_dictionary("Mieliepap is nice", entries)) == "mieliepap is nice"
    assert _text(apply_dictionary("we had mielie pap", entries)) == "we had mieliepap"
    # Something fuzzier (melly pap) needs a hint, so it is left alone here.
    assert _text(apply_dictionary("we had melly pap", entries)) == "we had melly pap"


def test_ac_5_1_b_multiword_hyphen_variant():
    entries = [DictEntry(canonical="Center Parcs")]
    assert _text(apply_dictionary("book center-parcs today", entries)) == "book Center Parcs today"
    assert _text(apply_dictionary("book center parcs today", entries)) == "book Center Parcs today"


def test_dictionary_does_not_match_unrelated_words():
    entries = [DictEntry(canonical="colour")]
    # Same letters only near-miss; "color" differs in letters, so untouched here
    # (the British pass handles color -> colour separately).
    assert _text(apply_dictionary("the color red", entries)) == "the color red"


def test_ac_5_3_a_plain_editable_file(data):
    store.add_entry(data.dictionary_path, "Dtrb")
    store.add_entry(data.dictionary_path, "mieliepap", ["melly pap"])
    # The file is plain text a person can read and edit.
    text = data.dictionary_path.read_text()
    assert "Dtrb" in text
    assert "mieliepap = melly pap" in text
    # An external edit is picked up on the next read.
    data.dictionary_path.write_text("client-x = klient ex\n")
    entries = store.read_entries(data.dictionary_path)
    assert entries[0].canonical == "client-x"
    assert entries[0].hints == ["klient ex"]


def test_ac_5_4_a_add_edit_delete(data):
    store.add_entry(data.dictionary_path, "Workato")
    assert any(e.canonical == "Workato" for e in store.read_entries(data.dictionary_path))
    assert store.remove_entry(data.dictionary_path, "Workato")
    assert not any(e.canonical == "Workato" for e in store.read_entries(data.dictionary_path))
    # A deleted entry stops being applied immediately.
    entries = store.read_entries(data.dictionary_path)
    assert _text(apply_dictionary("use Workato here", entries)) == "use Workato here"


def test_ac_5_2_a_single_word_change_offer():
    # A two-word mishearing collapsing to one word is a clean, anchored fix.
    change = single_word_change("we ate melly pap", "we ate mieliepap")
    assert change is not None
    assert change.heard == "melly pap"
    assert change.corrected == "mieliepap"
    # A plain single-word swap works too.
    swap = single_word_change("book it monday", "book it tuesday")
    assert swap is not None and swap.heard == "monday" and swap.corrected == "tuesday"
    # No offer when nothing changed or the whole sentence was rewritten.
    assert single_word_change("same text", "same text") is None
    assert single_word_change("a b c", "x y z") is None


def test_ac_5_2_b_accepted_correction_applies_next_time(data):
    store.add_entry(data.dictionary_path, "mieliepap", ["melly pap"])
    entries = store.read_entries(data.dictionary_path)
    result = default_pipeline().run("we ate melly pap", _ctx(entries))
    assert "mieliepap" in result.text


def test_ac_5_5_a_cross_link_entry_to_dictation(conn, data):
    from wordflow.history import store as history

    dictation_id = history.create_dictation(
        conn, model="parakeet", raw_text="melly pap", cleaned_text="melly pap")
    store.add_entry(data.dictionary_path, "mieliepap", ["melly pap"])
    store.record_link(conn, "mieliepap", dictation_id, ["melly pap"])
    # Forward: the entry knows its source dictation.
    assert store.entry_source_dictation(conn, "mieliepap") == dictation_id
    # Reverse: the dictation knows which entry it taught (AC-8.3-c).
    assert store.entries_taught_by(conn, dictation_id) == ["mieliepap"]
