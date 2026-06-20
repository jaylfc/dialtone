"""Multi-user accounts for the dashboard (Phase 1).

JSON-backed and dependency-free (uses werkzeug, which Flask already ships), to
match the existing voicemail-metadata storage pattern and stay offline-first.

A user record:
  {id, username, display_name, password_hash, role, extension, mailbox, active, created}

Roles: "admin" (full access) | "user" (own mailbox + calls).
Secrets (password_hash) never leave this module except via _public() stripping.
"""

import json
import threading
import time
import secrets
from pathlib import Path

from werkzeug.security import generate_password_hash, check_password_hash

ACCOUNTS_FILE = Path(__file__).parent / "users.json"
ROLES = ("admin", "user")
_lock = threading.RLock()


def _load():
    try:
        return json.loads(ACCOUNTS_FILE.read_text())
    except (FileNotFoundError, ValueError):
        return []


def _save(users):
    ACCOUNTS_FILE.write_text(json.dumps(users, indent=2))
    try:
        ACCOUNTS_FILE.chmod(0o600)  # contains password hashes
    except OSError:
        pass


def _public(u):
    """User dict without the password hash, safe to return over the API."""
    return {k: v for k, v in u.items() if k != "password_hash"}


def count():
    with _lock:
        return len(_load())


def list_users():
    with _lock:
        return [_public(u) for u in _load()]


def get(user_id):
    with _lock:
        for u in _load():
            if u["id"] == user_id:
                return _public(u)
    return None


def create(username, password, display_name="", role="user", extension="", mailbox=""):
    username = (username or "").strip()
    if not username or not password:
        raise ValueError("username and password are required")
    if role not in ROLES:
        raise ValueError("invalid role")
    with _lock:
        users = _load()
        if any(u["username"].lower() == username.lower() for u in users):
            raise ValueError("username already exists")
        user = {
            "id": secrets.token_hex(8),
            "username": username,
            "display_name": display_name or username,
            "password_hash": generate_password_hash(password),
            "role": role,
            "extension": str(extension or "").strip(),
            "mailbox": (mailbox or username).strip().lower(),
            "active": True,
            "created": time.time(),
        }
        users.append(user)
        _save(users)
        return _public(user)


def update(user_id, **fields):
    with _lock:
        users = _load()
        for u in users:
            if u["id"] != user_id:
                continue
            pw = fields.pop("password", None)
            if pw:
                u["password_hash"] = generate_password_hash(pw)
            if "role" in fields and fields["role"] not in ROLES:
                raise ValueError("invalid role")
            for k in ("display_name", "role", "extension", "mailbox", "active"):
                if k in fields and fields[k] is not None:
                    u[k] = fields[k]
            _save(users)
            return _public(u)
    return None


def delete(user_id):
    with _lock:
        users = _load()
        remaining = [u for u in users if u["id"] != user_id]
        if len(remaining) == len(users):
            return False
        _save(remaining)
        return True


def verify(username, password):
    """Return the public user dict on valid credentials, else None."""
    with _lock:
        for u in _load():
            if u["username"].lower() == (username or "").lower():
                if u.get("active", True) and check_password_hash(u["password_hash"], password or ""):
                    return _public(u)
                return None
    return None
