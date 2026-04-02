import os
import signal

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

from keypal.channels.telegram import chat_service


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_user and update.message:
        name = update.effective_user.first_name
        await update.message.reply_text(f"Hey {name}! I'm Keypal, your personal confidant. How can I help you today?")


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message:
        from keypal.config import settings

        lines = [
            "Just send me a message and I'll do my best to help!\n",
            "*Commands:*",
            "/services — Manage hosted prototypes",
            "/schedules — Manage scheduled tasks",
            "/mcp — Manage MCP server integrations",
        ]
        if settings.enable_git:
            lines.append("/git — View pending commits & push")
        lines.extend(
            [
                "/usage — View token spending",
                "/restart — Restart the bot",
                "/reset — Start a fresh conversation",
                "/help — Show this message",
            ]
        )
        await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def reset_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_user and update.message:
        await chat_service.reset_session(update.effective_user.id)
        await update.message.reply_text("Fresh start! What's on your mind?")


async def usage_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.effective_user and update.message:
        stats = chat_service.get_usage(update.effective_user.id)
        await update.message.reply_text(
            f"*Session Usage*\nMessages: {stats.message_count}\nCost: ${stats.total_cost_usd:.4f}",
            parse_mode="Markdown",
        )


async def restart_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Restart the bot. Guardian will auto-restart the process."""
    if update.message:
        await update.message.reply_text("Restarting... be right back ~")
        # Exit with non-zero so guardian restarts us
        os.kill(os.getpid(), signal.SIGTERM)


def register_command_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("reset", reset_command))
    application.add_handler(CommandHandler("usage", usage_command))
    application.add_handler(CommandHandler("restart", restart_command))
