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
    if not script.exists():
        logger.error("Script not found: %s", script)
        return {"status": "error", "message": f"Script not found: {name}"}
    result = subprocess.run(
        [str(script), *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.warning("Script %s failed (exit %d): %s", name, result.returncode, result.stderr)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        logger.error("Script %s returned invalid JSON: stdout=%r stderr=%r", name, result.stdout, result.stderr)
        return {"status": "error", "message": result.stderr or result.stdout or "Unknown error"}


AVAILABLE_MCPS: dict[str, tuple[str, list[str]]] = {
    "playwright": ("npx", ["-y", "@playwright/mcp@latest"]),
    "browser": ("npx", ["@anthropic-ai/mcp-browser"]),
    "fetch": ("npx", ["@anthropic-ai/mcp-fetch"]),
    "filesystem": ("npx", ["@anthropic-ai/mcp-filesystem", "~/"]),
    "github": ("npx", ["@anthropic-ai/mcp-github"]),
    "slack": ("npx", ["@anthropic-ai/mcp-slack"]),
    "postgres": ("npx", ["@anthropic-ai/mcp-postgres"]),
    "sqlite": ("npx", ["@anthropic-ai/mcp-sqlite"]),
}


def _build_mcp_keyboard(servers: list[dict]) -> InlineKeyboardMarkup:
    installed = {srv["name"] for srv in servers}
    buttons = []

    # Installed MCPs — show Uninstall button
    for srv in servers:
        name = srv["name"]
        cmd = srv.get("command", "")
        buttons.append(
            [
                InlineKeyboardButton(f"🔌 {name} ({cmd})", callback_data=f"mcp:noop:{name}"),
                InlineKeyboardButton("Uninstall", callback_data=f"mcp:remove:{name}"),
            ]
        )

    # Available but not installed — show Install button
    not_installed = [n for n in AVAILABLE_MCPS if n not in installed]
    for name in not_installed:
        buttons.append(
            [
                InlineKeyboardButton(f"  {name}", callback_data=f"mcp:noop:{name}"),
                InlineKeyboardButton("Install", callback_data=f"mcp:install:{name}"),
            ]
        )

    buttons.append([InlineKeyboardButton("🔄 Refresh", callback_data="mcp:refresh")])
    return InlineKeyboardMarkup(buttons)


async def mcp_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    data = _run_script("list-mcp.sh")

    # Script error — show the actual problem instead of "no MCPs"
    if isinstance(data, dict) and data.get("status") == "error":
        logger.error("list-mcp.sh error: %s", data.get("message"))
        await update.message.reply_text(
            "Failed to list MCP servers. Check logs for details.\nTry asking me to list MCP servers instead.",
        )
        return

    servers = data if isinstance(data, list) else []
    installed_count = len(servers)
    keyboard = _build_mcp_keyboard(servers)
    await update.message.reply_text(
        f"🔌 *MCP Servers* ({installed_count} installed)",
        parse_mode="Markdown",
        reply_markup=keyboard,
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
        servers = data if isinstance(data, list) else []
        keyboard = _build_mcp_keyboard(servers)
        await query.edit_message_text(
            f"🔌 *MCP Servers* ({len(servers)} installed)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )
        return

    if action == "install":
        mcp_info = AVAILABLE_MCPS.get(name)
        if not mcp_info:
            await query.edit_message_text(f"Unknown MCP: {name}")
            return
        cmd, args = mcp_info
        result = _run_script("install-mcp.sh", name, cmd, *args)
        if result.get("status") == "ok":
            msg = f"✅ Installed *{name}*. Restart bot to activate."
        else:
            msg = f"Error: {result.get('message')}"

        data = _run_script("list-mcp.sh")
        servers = data if isinstance(data, list) else []
        keyboard = _build_mcp_keyboard(servers)
        count = sum(1 for s in servers if s.get("source") == "native" or "source" not in s)
        await query.edit_message_text(
            f"{msg}\n\n🔌 *MCP Servers* ({count} installed)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )
        return

    if action == "remove":
        result = _run_script("uninstall-mcp.sh", name)
        if result.get("status") == "ok":
            msg = f"✅ Removed *{name}*. Restart bot to apply."
        else:
            msg = f"Error: {result.get('message')}"

        data = _run_script("list-mcp.sh")
        servers = data if isinstance(data, list) else []
        keyboard = _build_mcp_keyboard(servers)
        count = sum(1 for s in servers if s.get("source") == "native" or "source" not in s)
        await query.edit_message_text(
            f"{msg}\n\n🔌 *MCP Servers* ({count} installed)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )


def register_mcp_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("mcp", mcp_command))
    application.add_handler(CallbackQueryHandler(mcp_callback, pattern=r"^mcp:"))
