"""Phase 1 — multi-user accounts: store + auth/RBAC + mailbox scoping."""

import pytest

import accounts
import server


def _fresh(monkeypatch, tmp_path):
    """Isolate the accounts store to a temp file."""
    monkeypatch.setattr(accounts, "ACCOUNTS_FILE", tmp_path / "users.json")


# ── accounts store ────────────────────────────────────────────────────────────

class TestAccountsStore:
    def test_create_verify_public(self, monkeypatch, tmp_path):
        _fresh(monkeypatch, tmp_path)
        u = accounts.create("alice", "s3cret", display_name="Alice", role="admin", extension="101")
        assert u["username"] == "alice" and u["role"] == "admin" and u["extension"] == "101"
        assert "password_hash" not in u                       # never leaks
        assert accounts.verify("alice", "s3cret")["id"] == u["id"]
        assert accounts.verify("alice", "wrong") is None
        assert accounts.verify("ALICE", "s3cret") is not None  # case-insensitive username

    def test_duplicate_rejected(self, monkeypatch, tmp_path):
        _fresh(monkeypatch, tmp_path)
        accounts.create("bob", "pw")
        with pytest.raises(ValueError):
            accounts.create("BOB", "pw2")

    def test_inactive_cannot_verify(self, monkeypatch, tmp_path):
        _fresh(monkeypatch, tmp_path)
        u = accounts.create("carol", "pw")
        accounts.update(u["id"], active=False)
        assert accounts.verify("carol", "pw") is None

    def test_update_password_and_delete(self, monkeypatch, tmp_path):
        _fresh(monkeypatch, tmp_path)
        u = accounts.create("dave", "old")
        accounts.update(u["id"], password="new")
        assert accounts.verify("dave", "old") is None
        assert accounts.verify("dave", "new") is not None
        assert accounts.delete(u["id"]) is True
        assert accounts.get(u["id"]) is None

    def test_mailbox_defaults_to_username(self, monkeypatch, tmp_path):
        _fresh(monkeypatch, tmp_path)
        assert accounts.create("Eve", "pw")["mailbox"] == "eve"


# ── auth + RBAC integration ───────────────────────────────────────────────────

def _client(monkeypatch, tmp_path, token="secret"):
    _fresh(monkeypatch, tmp_path)
    monkeypatch.setattr(server, "DASHBOARD_TOKEN", token)
    server.dashboard_sessions.clear()
    server.login_attempts.clear()
    return server.dashboard_app.test_client()


class TestAuth:
    def test_token_login_backcompat(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path, token="tok123")
        r = c.post("/login", json={"password": "tok123"})   # no username = token login
        assert r.status_code == 200 and r.get_json()["status"] == "ok"
        assert c.get("/api/me").get_json()["role"] == "admin"

    def test_password_login(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("alice", "pw", role="user", mailbox="alice")
        assert c.post("/login", json={"username": "alice", "password": "pw"}).status_code == 200
        me = c.get("/api/me").get_json()
        assert me["username"] == "alice" and me["role"] == "user"

    def test_bad_password_401(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("alice", "pw")
        assert c.post("/login", json={"username": "alice", "password": "nope"}).status_code == 401

    def test_unauthenticated_blocked(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("alice", "pw")
        assert c.get("/api/me").status_code == 401

    def test_non_admin_forbidden(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("alice", "pw", role="user")
        c.post("/login", json={"username": "alice", "password": "pw"})
        assert c.get("/api/users").status_code == 403            # user mgmt = admin only
        assert c.post("/api/settings", json={"COMPANY_NAME": "X"}).status_code == 403

    def test_admin_manages_users(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("boss", "pw", role="admin")
        c.post("/login", json={"username": "boss", "password": "pw"})
        assert c.get("/api/users").status_code == 200
        assert c.post("/api/users", json={"username": "newbie", "password": "pw2"}).status_code == 201

    def test_mailbox_scoping(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        monkeypatch.setattr(server, "load_voicemails", lambda: [
            {"sid": "A", "mailbox": "alice"}, {"sid": "B", "mailbox": "general"}])
        accounts.create("alice", "pw", role="user", mailbox="alice")
        c.post("/login", json={"username": "alice", "password": "pw"})
        assert [v["sid"] for v in c.get("/voicemails").get_json()] == ["A"]  # only her mailbox


class TestVoicemailAuthz:
    """Every voicemail route is mailbox-scoped (not just the list) — IDOR guard."""

    def _alice(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        monkeypatch.setattr(server, "load_voicemails", lambda: [
            {"sid": "A", "mailbox": "alice", "from": "+111", "transcript": "ALICEVM"},
            {"sid": "B", "mailbox": "bob", "from": "+222", "transcript": "BOBVM"}])
        monkeypatch.setattr(server, "save_voicemails", lambda vms: None)
        accounts.create("alice", "pw", role="user", mailbox="alice")
        c.post("/login", json={"username": "alice", "password": "pw"})
        return c

    def test_cannot_delete_other_mailbox(self, monkeypatch, tmp_path):
        c = self._alice(monkeypatch, tmp_path)
        assert c.delete("/voicemails/B").status_code == 404   # bob's -> hidden
        assert c.delete("/voicemails/A").status_code == 200   # her own

    def test_cannot_fetch_other_mailbox_audio(self, monkeypatch, tmp_path):
        c = self._alice(monkeypatch, tmp_path)
        assert c.get("/voicemails/B/audio").status_code == 404  # scoped before file check

    def test_export_is_scoped(self, monkeypatch, tmp_path):
        c = self._alice(monkeypatch, tmp_path)
        body = c.get("/export/transcripts").get_data(as_text=True)
        assert "ALICEVM" in body and "BOBVM" not in body


class TestLoginRateLimit:
    def test_account_lockout_survives_ip_spoof(self, monkeypatch, tmp_path):
        c = _client(monkeypatch, tmp_path)
        accounts.create("alice", "pw")
        for i in range(server.PIN_MAX_ATTEMPTS):  # rotate the spoofable header each time
            r = c.post("/login", json={"username": "alice", "password": "wrong"},
                       headers={"X-Forwarded-For": f"9.9.9.{i}"})
            assert r.status_code == 401
        # keyed on the account, not the (spoofed) IP -> still locked
        r = c.post("/login", json={"username": "alice", "password": "wrong"},
                   headers={"X-Forwarded-For": "9.9.9.250"})
        assert r.status_code == 429
