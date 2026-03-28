"""Telegram handlers for /services command with inline keyboard."""

import json
import logging
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes

logger = logging.getLogger(__name__)

SCRIPTS = {
    "list": "list-services.sh",
    "stop": "stop-service.sh",
    "clear": "clear-service.sh",
    "deploy": "deploy-prototype.sh",
}


def _run_script(name: str, *args: str) -> dict:
    from pathlib import Path

    script = Path.home() / ".claude" / "scripts" / name
    result = subprocess.run([str(script), *args], capture_output=True, text=True)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"status": "error", "message": result.stderr or result.stdout or "Unknown error"}


def _build_service_keyboard(services: list[dict]) -> InlineKeyboardMarkup:
    buttons = []
    for svc in services:
        name = svc["name"]
        status = svc.get("status", "unknown")
        url = svc.get("url", "")
        row = []
        if url and status == "running":
            row.append(InlineKeyboardButton("🔗 Open", url=url))
        if status == "running":
            row.append(InlineKeyboardButton("⏹ Stop", callback_data=f"svc:stop:{name}"))
        else:
            row.append(InlineKeyboardButton("▶️ Restart", callback_data=f"svc:restart:{name}"))
        row.append(InlineKeyboardButton("🗑 Delete", callback_data=f"svc:clear:{name}"))
        icon = "🟢" if status == "running" else "🔴"
        port = svc.get("port", "?")
        buttons.append([InlineKeyboardButton(f"{icon} {name} :{port}", callback_data=f"svc:noop:{name}")])
        buttons.append(row)
    buttons.append([InlineKeyboardButton("🔄 Refresh", callback_data="svc:refresh")])
    return InlineKeyboardMarkup(buttons)


async def services_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    data = _run_script(SCRIPTS["list"])
    if isinstance(data, list) and len(data) > 0:
        keyboard = _build_service_keyboard(data)
        await update.message.reply_text("📋 *Services*", parse_mode="Markdown", reply_markup=keyboard)
    else:
        await update.message.reply_text("No services running. Send me a message to build something!")


async def services_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("svc:"):
        return
    await query.answer()

    parts = query.data.split(":", 2)
    action = parts[1] if len(parts) > 1 else ""
    name = parts[2] if len(parts) > 2 else ""

    if action == "refresh":
        data = _run_script(SCRIPTS["list"])
        if isinstance(data, list) and len(data) > 0:
            keyboard = _build_service_keyboard(data)
            await query.edit_message_text("📋 *Services*", parse_mode="Markdown", reply_markup=keyboard)
        else:
            await query.edit_message_text("No services running.")
        return

    if action == "noop":
        return

    if action == "stop":
        result = _run_script(SCRIPTS["stop"], name)
        msg = f"⏹ Stopped *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
    elif action == "clear":
        result = _run_script(SCRIPTS["clear"], name)
        msg = f"🗑 Deleted *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
    elif action == "restart":
        # Get dir from registry to re-deploy
        all_services = _run_script(SCRIPTS["list"])
        svc = next((s for s in all_services if s["name"] == name), None) if isinstance(all_services, list) else None
        if svc and svc.get("dir"):
            result = _run_script(SCRIPTS["deploy"], name, svc["dir"])
            msg = f"▶️ Restarted *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
        else:
            msg = f"Cannot restart *{name}*: project directory not found"
    else:
        msg = "Unknown action"

    # Refresh the list after action
    data = _run_script(SCRIPTS["list"])
    if isinstance(data, list) and len(data) > 0:
        keyboard = _build_service_keyboard(data)
        await query.edit_message_text(f"{msg}\n\n📋 *Services*", parse_mode="Markdown", reply_markup=keyboard)
    else:
        await query.edit_message_text(f"{msg}\n\nNo services running.")


def register_service_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("services", services_command))
    application.add_handler(CallbackQueryHandler(services_callback, pattern=r"^svc:"))
