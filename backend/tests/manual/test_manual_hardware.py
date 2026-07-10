"""Placeholders for the written hardware checklist (docs/MANUAL_CHECKLIST.md).
Always skipped: a person runs these on a real Mac, they are not automated."""

import pytest

pytestmark = pytest.mark.manual


@pytest.mark.skip(reason="manual hardware checklist item; see docs/MANUAL_CHECKLIST.md")
def test_manual_placeholder():
    pass
