"""Telegram handlers for /mcp command with inline keyboard."""

import json
import logging
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)

logger = logging.getLogger(__name__)


def _run_script(name: str, *args: str) -> dict | list:
    from pathlib import Path

    script = Path.home() / ".claude" / "scripts" / name
    result = subprocess.run(
        [str(script), *args],
        capture_output=True,
        text=True,
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"status": "error", "message": result.stderr or result.stdout or "Unknown error"}


def _build_mcp_keyboard(servers: list[dict]) -> InlineKeyboardMarkup:
    buttons = []
    for srv in servers:
        name = srv["name"]
        cmd = srv.get("command", "")
        buttons.append(
            [
                InlineKeyboardButton(f"🔌 {name} ({cmd})", callback_data=f"mcp:noop:{name}"),
                InlineKeyboardButton("🗑", callback_data=f"mcp:remove:{name}"),
            ]
        )
    buttons.append([InlineKeyboardButton("🔄 Refresh", callback_data="mcp:refresh")])
    return InlineKeyboardMarkup(buttons)


async def mcp_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    data = _run_script("list-mcp.sh")
    if isinstance(data, list) and len(data) > 0:
        keyboard = _build_mcp_keyboard(data)
        await update.message.reply_text(
            f"🔌 *MCP Servers* ({len(data)} installed)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )
    else:
        await update.message.reply_text(
            "No MCP servers installed. Ask me to add capabilities like "
            "browser automation, calendar, or database access!",
        )


async def mcp_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("mcp:"):
        return
    await query.answer()

    parts = query.data.split(":", 2)
    action = parts[1] if len(parts) > 1 else ""
    name = parts[2] if len(parts) > 2 else ""

    if action == "noop":
        return

    if action == "refresh":
        data = _run_script("list-mcp.sh")
        if isinstance(data, list) and len(data) > 0:
            keyboard = _build_mcp_keyboard(data)
            await query.edit_message_text(
                f"🔌 *MCP Servers* ({len(data)} installed)",
                parse_mode="Markdown",
                reply_markup=keyboard,
            )
        else:
            await query.edit_message_text("No MCP servers installed.")
        return

    if action == "remove":
        result = _run_script("uninstall-mcp.sh", name)
        if result.get("status") == "ok":
            msg = f"🗑 Removed *{name}*. Restart bot to apply."
        else:
            msg = f"Error: {result.get('message')}"

        data = _run_script("list-mcp.sh")
        if isinstance(data, list) and len(data) > 0:
            keyboard = _build_mcp_keyboard(data)
            await query.edit_message_text(
                f"{msg}\n\n🔌 *MCP Servers* ({len(data)} installed)",
                parse_mode="Markdown",
                reply_markup=keyboard,
            )
        else:
            await query.edit_message_text(
                f"{msg}\n\nNo MCP servers installed.",
                parse_mode="Markdown",
            )


def register_mcp_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("mcp", mcp_command))
    application.add_handler(CallbackQueryHandler(mcp_callback, pattern=r"^mcp:"))
