from keypal.channels.telegram.prompt import GIT_PROMPT_ADDON, TELEGRAM_SYSTEM_PROMPT
from keypal.config import settings
from keypal.services.chat import ChatService

_prompt = TELEGRAM_SYSTEM_PROMPT
if settings.enable_git:
    _prompt += GIT_PROMPT_ADDON

chat_service = ChatService(system_prompt=_prompt, session_prefix="tg", model=settings.tg_claude_model)
