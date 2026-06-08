"""Shared fixtures for the server test suite.

Env is forced before importing `server` so the module initialises deterministically
(no local-voice pip install, signature validation on, no live Deepgram).
"""

import os
import sys
from pathlib import Path

os.environ.setdefault("USE_LOCAL_VOICE", "false")
os.environ.setdefault("TWILIO_AUTH_TOKEN", "faketwiliotoken")
os.environ.setdefault("VALIDATE_TWILIO_SIGNATURE", "true")
os.environ.setdefault("DEEPGRAM_API_KEY", "")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import server  # noqa: E402
import pytest  # noqa: E402


_OVERRIDE_KEYS = (
    "VALIDATE_TWILIO_SIGNATURE", "WEBHOOK_URL_OVERRIDE", "WEBHOOK_PORT",
    "DASHBOARD_PORT", "PIN_MAX_ATTEMPTS", "PIN_LOCKOUT_WINDOW",
)


@pytest.fixture(autouse=True)
def _restore_override_env():
    """Several settings are now read live from os.environ; restore them after each
    test so update_setting()'s os.environ side effects don't leak across tests."""
    saved = {k: os.environ.get(k) for k in _OVERRIDE_KEYS}
    yield
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


@pytest.fixture()
def webhook_client():
    server.pin_attempts.clear()
    return server.webhook_app.test_client()
