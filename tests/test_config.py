import pytest


def test_allowed_tg_user_ids_parsing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TG_BOT_TOKEN", "test")
    monkeypatch.setenv("ALLOWED_TG_USERS", "111, 222, 333")

    from keypal.config import Settings

    s = Settings()
    assert s.allowed_tg_user_ids == {111, 222, 333}


def test_allowed_tg_user_ids_empty(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TG_BOT_TOKEN", "test")
    monkeypatch.setenv("ALLOWED_TG_USERS", "")

    from keypal.config import Settings

    s = Settings()
    assert s.allowed_tg_user_ids == set()


def test_allowed_tg_user_ids_single(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TG_BOT_TOKEN", "test")
    monkeypatch.setenv("ALLOWED_TG_USERS", "123456789")

    from keypal.config import Settings

    s = Settings()
    assert s.allowed_tg_user_ids == {123456789}


def test_default_values(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TG_BOT_TOKEN", "test-token")
    # Remove .env file influence
    monkeypatch.delenv("ALLOWED_TG_USERS", raising=False)
    monkeypatch.delenv("CLAUDE_MODEL", raising=False)
    monkeypatch.delenv("ENABLE_GIT", raising=False)
    monkeypatch.delenv("LOG_LEVEL", raising=False)

    from keypal.config import Settings

    s = Settings(_env_file=None)  # type: ignore[call-arg]
    assert s.tg_bot_token == "test-token"
    assert s.claude_model == "sonnet"
    assert s.enable_git is False
    assert s.log_level == "INFO"
