import logging
import random
from pathlib import Path

from telegram import Update
from telegram.ext import Application, ContextTypes, MessageHandler, filters

from keypal.channels.telegram import chat_service
from keypal.services.chat import DraftCallback, FileCallback, StatusCallback
from keypal.services.queue import MessageQueue

logger = logging.getLogger(__name__)

TG_MAX_MESSAGE_LENGTH = 4096
UPLOADS_DIR = Path.home() / "uploads"


def _make_draft_id() -> int:
    return random.randint(1, 2**31 - 1)


def _truncate(text: str, limit: int = TG_MAX_MESSAGE_LENGTH) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 20] + "\n\n...(truncated)"


def _make_draft_callback(bot: object, chat_id: int) -> DraftCallback:
    """Create a draft callback bound to a specific chat."""
    draft_id = _make_draft_id()

    async def on_draft(text: str) -> None:
        try:
            await bot.send_message_draft(  # type: ignore[attr-defined]
                chat_id=chat_id,
                draft_id=draft_id,
                text=_truncate(text),
            )
        except Exception:
            logger.debug("send_message_draft failed", exc_info=True)

    return on_draft


def _make_status_callback(bot: object, chat_id: int) -> StatusCallback:
    """Create a status callback that sends tool status as separate messages."""
    last_status_msg_id: list[int | None] = [None]

    async def on_status(text: str) -> None:
        import contextlib

        try:
            if last_status_msg_id[0] is not None:
                with contextlib.suppress(Exception):
                    await bot.delete_message(chat_id=chat_id, message_id=last_status_msg_id[0])  # type: ignore[attr-defined]
            msg = await bot.send_message(chat_id=chat_id, text=text)  # type: ignore[attr-defined]
            last_status_msg_id[0] = msg.message_id
        except Exception:
            logger.debug("Status message failed", exc_info=True)

    return on_status


_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
_RELEVANT_PREFIXES = tuple(str(Path.home() / d) for d in ("prototypes", "uploads", "schedules"))


def _check_file(file_path: str) -> tuple[bool, str, str]:
    """Check if a file should be sent (sync, runs in thread)."""
    import os

    if not os.path.isfile(file_path):
        return False, "", ""
    if os.path.getsize(file_path) > 50 * 1024 * 1024:
        return False, "", ""
    if not file_path.startswith(_RELEVANT_PREFIXES):
        return False, "", ""
    ext = os.path.splitext(file_path)[1].lower()
    name = os.path.basename(file_path)
    return True, ext, name


def _read_file(file_path: str) -> bytes:
    """Read file contents (sync, runs in thread)."""
    with open(file_path, "rb") as f:
        return f.read()


def _make_file_callback(bot: object, chat_id: int) -> FileCallback:
    """Create a file callback that sends files written by Claude to the user."""
    import asyncio

    async def on_file(file_path: str) -> None:
        ok, ext, name = await asyncio.to_thread(_check_file, file_path)
        if not ok:
            return
        try:
            data = await asyncio.to_thread(_read_file, file_path)
            if ext in _IMAGE_EXTENSIONS:
                await bot.send_photo(chat_id=chat_id, photo=data)  # type: ignore[attr-defined]
            else:
                await bot.send_document(chat_id=chat_id, document=data, filename=name)  # type: ignore[attr-defined]
        except Exception:
            logger.debug("Failed to send file %s", file_path, exc_info=True)

    return on_file


async def _chat_handler(
    user_id: int,
    message: str,
    on_draft: DraftCallback | None = None,
    on_status: StatusCallback | None = None,
    on_file: FileCallback | None = None,
) -> str:
    """Queue-compatible handler that forwards to ChatService."""
    return await chat_service.reply(user_id, message, on_draft=on_draft, on_status=on_status, on_file=on_file)


message_queue = MessageQueue(handler=_chat_handler)


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.text or not update.effective_user:
        return

    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else user_id
    text = update.message.text

    # Check for pending modify context from schedule callback
    pending = (context.user_data or {}).pop("pending_modify", None)
    if pending:
        name = pending["name"]
        text = f"Modify the scheduled task '{name}' (current: {pending.get('description', '')}). User says: {text}"

    on_draft = _make_draft_callback(context.bot, chat_id)
    on_status = _make_status_callback(context.bot, chat_id)
    on_file = _make_file_callback(context.bot, chat_id)

    # Show typing indicator while processing
    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    try:
        response = await message_queue.enqueue(
            user_id,
            text,
            on_draft=on_draft,
            on_status=on_status,
            on_file=on_file,
        )
        await update.message.reply_text(_truncate(response))
    except Exception:
        logger.exception("Failed to process message for user %d", user_id)
        await update.message.reply_text("Sorry, something went wrong. Please try again.")


async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle photo uploads — download and tell Claude about it."""
    if not update.message or not update.effective_user:
        return

    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else user_id

    photo = update.message.photo[-1] if update.message.photo else None
    if not photo:
        return

    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    file = await context.bot.get_file(photo.file_id)
    file_path = UPLOADS_DIR / f"{photo.file_unique_id}.jpg"
    await file.download_to_drive(str(file_path))

    caption = update.message.caption or ""
    caption_part = f" — {caption}" if caption else ""
    message = f"[User uploaded an image to {file_path}{caption_part}]. You can view it with the Read tool."

    on_draft = _make_draft_callback(context.bot, chat_id)
    on_status = _make_status_callback(context.bot, chat_id)
    on_file = _make_file_callback(context.bot, chat_id)

    try:
        response = await message_queue.enqueue(
            user_id,
            message,
            on_draft=on_draft,
            on_status=on_status,
            on_file=on_file,
        )
        await update.message.reply_text(_truncate(response))
    except Exception:
        logger.exception("Failed to process photo for user %d", user_id)
        await update.message.reply_text("Sorry, I couldn't process your image.")


async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle file uploads — download and tell Claude about it."""
    if not update.message or not update.message.document or not update.effective_user:
        return

    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else user_id
    doc = update.message.document

    # Download document
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    file = await context.bot.get_file(doc.file_id)
    file_name = doc.file_name or doc.file_unique_id
    file_path = UPLOADS_DIR / file_name
    await file.download_to_drive(str(file_path))

    caption = update.message.caption or ""
    mime = doc.mime_type or "unknown type"
    size = doc.file_size or 0
    caption_part = f" — {caption}" if caption else ""
    message = f"[User uploaded a file: {file_path} ({mime}, {size} bytes){caption_part}]. Read it with the Read tool."

    on_draft = _make_draft_callback(context.bot, chat_id)
    on_status = _make_status_callback(context.bot, chat_id)
    on_file = _make_file_callback(context.bot, chat_id)

    try:
        response = await message_queue.enqueue(
            user_id,
            message,
            on_draft=on_draft,
            on_status=on_status,
            on_file=on_file,
        )
        await update.message.reply_text(_truncate(response))
    except Exception:
        logger.exception("Failed to process document for user %d", user_id)
        await update.message.reply_text("Sorry, I couldn't process your file.")


def register_message_handlers(application: Application) -> None:  # type: ignore[type-arg]
    application.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    application.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
