"""Section 10: privacy and offline guarantees that can be checked statically in
the fast gate."""

import re
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[2] / "wordflow"

# Any URL other than these is a red flag in a fully local app.
ALLOWED_URL_HOSTS = {"127.0.0.1", "localhost"}
ANALYTICS_MARKERS = [
    "segment.io", "mixpanel", "amplitude", "sentry", "posthog",
    "google-analytics", "googletagmanager", "telemetry", "analytics.",
]


def _python_sources():
    return [p for p in PACKAGE.rglob("*.py")]


def test_ac_10_4_a_no_telemetry_endpoints():
    for path in _python_sources():
        text = path.read_text().lower()
        for marker in ANALYTICS_MARKERS:
            assert marker not in text, f"{path} mentions {marker!r}"


def test_ac_10_2_a_no_outbound_urls_in_runtime_code():
    url = re.compile(r"https?://([A-Za-z0-9.\-]+)")
    for path in _python_sources():
        for host in url.findall(path.read_text()):
            assert host in ALLOWED_URL_HOSTS, f"{path} references {host!r}"


def test_ac_10_2_b_offline_flags_pinned_in_main():
    main = (PACKAGE / "__main__.py").read_text()
    assert 'HF_HUB_OFFLINE' in main
    assert 'TRANSFORMERS_OFFLINE' in main
    # They are set before the offline libraries are imported.
    assert main.index("_pin_offline") < main.index("import uvicorn")
