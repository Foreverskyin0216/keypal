"""Telegram callback handler for dangerous command approval keyboards."""

import logging

from telegram import Update
from telegram.ext import Application, CallbackQueryHandler, ContextTypes

from keypal.services.chat import danger_gate

logger = logging.getLogger(__name__)


async def danger_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle [Allow] / [Deny] button taps on danger approval keyboards."""
    query = update.callback_query
    if not query or not query.data or not query.data.startswith("danger:"):
        return
    await query.answer()

    parts = query.data.split(":", 2)
    if len(parts) < 3:
        return

    action = parts[1]  # "allow" or "deny"
    approval_id = parts[2]

    allow = action == "allow"
    resolved = danger_gate.resolve(approval_id, allow)

    if resolved:
        icon = "\u2705" if allow else "\U0001f6ab"  # ✅ or 🚫
        label = "Allowed" if allow else "Denied"
        original = query.message.text if query.message else ""
        await query.edit_message_text(f"{icon} {label}\n\n{original}")
    else:
        await query.edit_message_text("\u23f0 This approval has expired.")


def register_danger_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(CallbackQueryHandler(danger_callback, pattern=r"^danger:"))
