from telegram import BotCommand
from telegram.ext import Application

from keypal.channels.telegram.handlers import register_handlers
from keypal.config import settings


def _build_commands() -> list[BotCommand]:
    commands = [
        BotCommand("start", "Start the bot"),
        BotCommand("help", "Show available commands"),
        BotCommand("services", "Manage hosted prototypes"),
        BotCommand("schedules", "Manage scheduled tasks"),
        BotCommand("mcp", "Manage MCP server integrations"),
    ]
    if settings.enable_git:
        commands.append(BotCommand("git", "View pending commits & push"))
    commands.extend(
        [
            BotCommand("usage", "View token spending"),
            BotCommand("restart", "Restart the bot"),
            BotCommand("reset", "Start a fresh conversation"),
        ]
    )
    return commands


async def post_init(application: Application) -> None:  # type: ignore[type-arg]
    import asyncio
    import contextlib
    import logging

    logger = logging.getLogger(__name__)

    # Retry set_my_commands with backoff (transient Telegram API timeouts)
    for attempt in range(3):
        try:
            await application.bot.set_my_commands(_build_commands())
            break
        except Exception as e:
            if attempt < 2:
                await asyncio.sleep(2**attempt)
            else:
                logger.warning("set_my_commands failed, continuing: %s", e)

    # Notify allowed users that bot is (back) online
    for uid in settings.allowed_tg_user_ids:
        with contextlib.suppress(Exception):
            await application.bot.send_message(chat_id=uid, text="I'm back :)")


def create_telegram_app() -> Application:  # type: ignore[type-arg]
    application = Application.builder().token(settings.tg_bot_token).post_init(post_init).build()
    register_handlers(application)
    return application
