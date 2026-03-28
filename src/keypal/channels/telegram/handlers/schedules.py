"""Telegram handlers for /schedules command with inline keyboard."""

import json
import logging
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CallbackQueryHandler, CommandHandler, ContextTypes

logger = logging.getLogger(__name__)


def _run_script(name: str, *args: str) -> dict | list:
    from pathlib import Path

    script = Path.home() / ".claude" / "scripts" / name
    result = subprocess.run([str(script), *args], capture_output=True, text=True)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"status": "error", "message": result.stderr or result.stdout or "Unknown error"}


def _cron_to_human(cron: str) -> str:
    """Simple cron to human-readable conversion for common patterns."""
    parts = cron.split()
    if len(parts) != 5:
        return cron
    minute, hour, dom, month, dow = parts

    if minute.startswith("*/"):
        return f"every {minute[2:]}min"
    if hour == "*" and minute != "*":
        return f"every hour at :{minute}"
    if hour != "*" and minute != "*" and dom == "*" and month == "*":
        if dow == "*":
            return f"daily {hour}:{minute.zfill(2)}"
        days = {"0": "Sun", "1": "Mon", "2": "Tue", "3": "Wed", "4": "Thu", "5": "Fri", "6": "Sat"}
        day_name = days.get(dow, dow)
        return f"{day_name} {hour}:{minute.zfill(2)}"
    return cron


def _build_schedule_keyboard(schedules: list[dict]) -> InlineKeyboardMarkup:
    buttons = []
    for task in schedules:
        name = task["name"]
        status = task.get("live_status", task.get("status", "unknown"))
        cron = task.get("cron", "")
        human_time = _cron_to_human(cron)

        label = f"{'🟢' if status == 'active' else '⏸'} {name} — {human_time}"
        buttons.append([InlineKeyboardButton(label, callback_data=f"sch:noop:{name}")])

        row = []
        if status == "active":
            row.append(InlineKeyboardButton("⏸ Pause", callback_data=f"sch:pause:{name}"))
        else:
            row.append(InlineKeyboardButton("▶️ Resume", callback_data=f"sch:resume:{name}"))
        row.append(InlineKeyboardButton("✏️ Modify", callback_data=f"sch:modify:{name}"))
        row.append(InlineKeyboardButton("🗑 Delete", callback_data=f"sch:clear:{name}"))
        buttons.append(row)

    buttons.append([InlineKeyboardButton("🔄 Refresh", callback_data="sch:refresh")])
    return InlineKeyboardMarkup(buttons)


async def schedules_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    data = _run_script("list-schedules.sh")
    if isinstance(data, list) and len(data) > 0:
        keyboard = _build_schedule_keyboard(data)
        await update.message.reply_text("📋 *Schedules*", parse_mode="Markdown", reply_markup=keyboard)
    else:
        await update.message.reply_text("No scheduled tasks. Tell me what you'd like to automate!")


async def _handle_modify(query, name: str, context: ContextTypes.DEFAULT_TYPE) -> None:  # type: ignore[no-untyped-def]
    """Ask user for new task description, then route to Claude Code."""
    # Get current task info
    schedules = _run_script("list-schedules.sh")
    task = next((s for s in schedules if s["name"] == name), None) if isinstance(schedules, list) else None
    desc = task.get("description", "") if task else ""
    cron = task.get("cron", "") if task else ""
    human_time = _cron_to_human(cron) if cron else ""

    prompt = f"I want to modify the scheduled task '{name}'"
    if desc:
        prompt += f" (currently: {desc}, runs {human_time})"
    prompt += ". What would you like to change? (schedule, content, or both)"

    await query.edit_message_text(
        f"✏️ *Modify: {name}*\n"
        f"Current: {desc}\n"
        f"Schedule: {human_time}\n\n"
        f"Tell me what you'd like to change — the schedule, the content, or both.",
        parse_mode="Markdown",
    )
    # Store context so the next text message gets routed with this context
    if context.user_data is not None:
        context.user_data["pending_modify"] = {"name": name, "description": desc, "cron": cron}


async def schedules_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("sch:"):
        return
    await query.answer()

    parts = query.data.split(":", 2)
    action = parts[1] if len(parts) > 1 else ""
    name = parts[2] if len(parts) > 2 else ""

    if action == "refresh":
        data = _run_script("list-schedules.sh")
        if isinstance(data, list) and len(data) > 0:
            keyboard = _build_schedule_keyboard(data)
            await query.edit_message_text("📋 *Schedules*", parse_mode="Markdown", reply_markup=keyboard)
        else:
            await query.edit_message_text("No scheduled tasks.")
        return

    if action == "noop":
        return

    if action == "modify":
        await _handle_modify(query, name, context)
        return

    if action == "pause":
        result = _run_script("pause-schedule.sh", name)
        msg = f"⏸ Paused *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
    elif action == "resume":
        result = _run_script("resume-schedule.sh", name)
        msg = f"▶️ Resumed *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
    elif action == "clear":
        result = _run_script("clear-schedule.sh", name)
        msg = f"🗑 Deleted *{name}*" if result.get("status") == "ok" else f"Error: {result.get('message')}"
    else:
        msg = "Unknown action"

    # Refresh list after action
    data = _run_script("list-schedules.sh")
    if isinstance(data, list) and len(data) > 0:
        keyboard = _build_schedule_keyboard(data)
        await query.edit_message_text(f"{msg}\n\n📋 *Schedules*", parse_mode="Markdown", reply_markup=keyboard)
    else:
        await query.edit_message_text(f"{msg}\n\nNo scheduled tasks.")


def register_schedule_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CommandHandler("schedules", schedules_command))
    application.add_handler(CallbackQueryHandler(schedules_callback, pattern=r"^sch:"))
