"""Telegram handlers for /plugins command with inline keyboard."""

import json
import logging
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes

logger = logging.getLogger(__name__)

ITEMS_PER_PAGE = 8


def _run_script(name: str, *args: str) -> dict | list:
    from pathlib import Path

    script = Path.home() / ".claude" / "scripts" / name
    result = subprocess.run([str(script), *args], capture_output=True, text=True)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"status": "error", "message": result.stderr or result.stdout or "Unknown error"}


def _build_plugin_keyboard(plugins: list[dict], page: int = 0) -> InlineKeyboardMarkup:
    start = page * ITEMS_PER_PAGE
    end = start + ITEMS_PER_PAGE
    page_plugins = plugins[start:end]
    total_pages = (len(plugins) + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE

    buttons = []
    for p in page_plugins:
        name = p["name"]
        installed = p.get("installed", False)
        icon = "✅" if installed else "⬜"
        buttons.append(
            [
                InlineKeyboardButton(f"{icon} {name}", callback_data=f"plg:noop:{name}"),
                InlineKeyboardButton(
                    "Uninstall" if installed else "Install",
                    callback_data=f"plg:{'uninstall' if installed else 'install'}:{name}",
                ),
            ]
        )

    nav_row = []
    if page > 0:
        nav_row.append(InlineKeyboardButton("◀ Prev", callback_data=f"plg:page:{page - 1}"))
    nav_row.append(InlineKeyboardButton(f"{page + 1}/{total_pages}", callback_data="plg:noop:page"))
    if end < len(plugins):
        nav_row.append(InlineKeyboardButton("Next ▶", callback_data=f"plg:page:{page + 1}"))
    buttons.append(nav_row)
    return InlineKeyboardMarkup(buttons)


async def plugins_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    data = _run_script("list-plugins.sh")
    if isinstance(data, list) and len(data) > 0:
        # Store full list in user_data for pagination
        if context.user_data is not None:
            context.user_data["plugins_list"] = data
        keyboard = _build_plugin_keyboard(data, page=0)
        installed_count = sum(1 for p in data if p.get("installed"))
        await update.message.reply_text(
            f"🧩 *Plugins* ({installed_count} installed / {len(data)} available)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )
    else:
        await update.message.reply_text("No plugins found.")


async def plugins_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("plg:"):
        return
    await query.answer()

    parts = query.data.split(":", 2)
    action = parts[1] if len(parts) > 1 else ""
    value = parts[2] if len(parts) > 2 else ""

    if action == "noop":
        return

    # Get cached plugin list or refresh
    plugins = (context.user_data or {}).get("plugins_list")

    if action == "page":
        page = int(value)
        if plugins:
            keyboard = _build_plugin_keyboard(plugins, page=page)
            installed_count = sum(1 for p in plugins if p.get("installed"))
            await query.edit_message_text(
                f"🧩 *Plugins* ({installed_count} installed / {len(plugins)} available)",
                parse_mode="Markdown",
                reply_markup=keyboard,
            )
        return

    if action == "install":
        result = _run_script("install-plugin.sh", value)
        if result.get("status") == "ok":
            msg = f"✅ Installed *{value}*. Restart session to activate."
        else:
            msg = f"Error: {result.get('message')}"
    elif action == "uninstall":
        result = _run_script("uninstall-plugin.sh", value)
        if result.get("status") == "ok":
            msg = f"❌ Uninstalled *{value}*. Restart session to apply."
        else:
            msg = f"Error: {result.get('message')}"
    else:
        msg = "Unknown action"

    # Refresh list
    data = _run_script("list-plugins.sh")
    if isinstance(data, list):
        if context.user_data is not None:
            context.user_data["plugins_list"] = data
        keyboard = _build_plugin_keyboard(data, page=0)
        installed_count = sum(1 for p in data if p.get("installed"))
        await query.edit_message_text(
            f"{msg}\n\n🧩 *Plugins* ({installed_count} installed / {len(data)} available)",
            parse_mode="Markdown",
            reply_markup=keyboard,
        )
    else:
        await query.edit_message_text(msg, parse_mode="Markdown")


def register_plugin_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("plugins", plugins_command))
    application.add_handler(CallbackQueryHandler(plugins_callback, pattern=r"^plg:"))
