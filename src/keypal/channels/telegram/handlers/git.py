"""Telegram handlers for /git command with inline keyboard."""

import logging
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes

logger = logging.getLogger(__name__)


def _git(cmd: str) -> str:
    """Run a git command in the project directory and return output."""
    from pathlib import Path

    project_dir = Path.home() / "Workspace" / "projects" / "keypal"
    result = subprocess.run(
        ["git"] + cmd.split(),
        capture_output=True,
        text=True,
        cwd=str(project_dir),
    )
    return (result.stdout + result.stderr).strip()


def _build_git_keyboard(has_unpushed: bool) -> InlineKeyboardMarkup:
    buttons = []
    if has_unpushed:
        buttons.append(
            [
                InlineKeyboardButton("🚀 Push", callback_data="git:push"),
                InlineKeyboardButton("❌ Cancel", callback_data="git:noop"),
            ]
        )
    buttons.append([InlineKeyboardButton("🔄 Refresh", callback_data="git:refresh")])
    return InlineKeyboardMarkup(buttons)


def _format_status() -> tuple[str, bool]:
    """Get git status summary and whether there are unpushed commits."""
    branch = _git("branch --show-current")
    log_unpushed = _git("log @{u}.. --oneline")
    has_unpushed = bool(log_unpushed.strip())

    status = _git("status --short")
    if not status and not has_unpushed:
        return "✅ Everything up to date.", False

    parts = [f"*Branch:* `{branch}`"]

    if has_unpushed:
        parts.append(f"\n*Unpushed commits:*\n```\n{log_unpushed}\n```")

    if status:
        parts.append(f"\n*Working tree:*\n```\n{status}\n```")

    return "\n".join(parts), has_unpushed


async def git_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return

    text, has_unpushed = _format_status()
    keyboard = _build_git_keyboard(has_unpushed)
    await update.message.reply_text(text, parse_mode="Markdown", reply_markup=keyboard)


async def git_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("git:"):
        return
    await query.answer()

    action = query.data.split(":")[1]

    if action == "noop":
        return

    if action == "push":
        result = _git("push")
        text, has_unpushed = _format_status()
        msg = f"🚀 *Pushed!*\n```\n{result}\n```\n\n{text}"
        keyboard = _build_git_keyboard(has_unpushed)
        await query.edit_message_text(msg, parse_mode="Markdown", reply_markup=keyboard)
        return

    if action == "refresh":
        text, has_unpushed = _format_status()
        keyboard = _build_git_keyboard(has_unpushed)
        await query.edit_message_text(text, parse_mode="Markdown", reply_markup=keyboard)


def register_git_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("git", git_command))
    application.add_handler(CallbackQueryHandler(git_callback, pattern=r"^git:"))
