"""Authentication filter for Telegram handlers."""

import logging

from telegram import Update
from telegram.ext import ContextTypes

from keypal.config import settings

logger = logging.getLogger(__name__)

_DENIED_CACHE: set[int] = set()
_WARNED_NO_WHITELIST = False


async def auth_check(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Block unauthorized users. Registered as a group -1 handler (runs before all others)."""
    global _WARNED_NO_WHITELIST
    allowed = settings.allowed_tg_user_ids
    if not allowed:
        if not _WARNED_NO_WHITELIST:
            _WARNED_NO_WHITELIST = True
            logger.warning("ALLOWED_TG_USERS is empty — bot is open to everyone!")
        return

    user = update.effective_user
    if user is None:
        return

    if user.id in allowed:
        return

    # Deny: log once per user, reply once per session
    if user.id not in _DENIED_CACHE:
        _DENIED_CACHE.add(user.id)
        logger.warning("Unauthorized user: %d (%s)", user.id, user.username or user.first_name)
        if update.message:
            await update.message.reply_text("Sorry, I'm a private bot. Contact the owner for access.")

    # Prevent further handler processing
    raise ApplicationHandlerStop()


# Import here to avoid circular
from telegram.ext import ApplicationHandlerStop  # noqa: E402
