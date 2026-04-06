from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    tg_bot_token: str
    claude_model: str = "sonnet"  # Default model for all channels
    tg_claude_model: str = ""  # Override model for Telegram (empty = use default)
    allowed_tg_users: str = ""  # Comma-separated Telegram user IDs, empty = allow all
    enable_git: bool = False  # Enable /git command and auto-commit
    log_level: str = "INFO"

    @property
    def allowed_tg_user_ids(self) -> set[int]:
        if not self.allowed_tg_users.strip():
            return set()
        return {int(uid.strip()) for uid in self.allowed_tg_users.split(",") if uid.strip()}


settings = Settings()  # type: ignore[call-arg]
