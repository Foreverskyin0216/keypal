from telegram import Update
from telegram.ext import Application, TypeHandler

from keypal.channels.telegram.auth import auth_check
from keypal.channels.telegram.handlers.commands import register_command_handlers
from keypal.channels.telegram.handlers.mcp import register_mcp_handlers
from keypal.channels.telegram.handlers.messages import register_message_handlers
from keypal.channels.telegram.handlers.plugins import register_plugin_handlers
from keypal.channels.telegram.handlers.schedules import register_schedule_handlers
from keypal.channels.telegram.handlers.services import register_service_handlers
from keypal.config import settings


def register_handlers(application: Application) -> None:  # type: ignore[type-arg]
    # Auth check runs first (group -1, before all other handlers)
    application.add_handler(TypeHandler(Update, auth_check), group=-1)

    register_command_handlers(application)
    register_service_handlers(application)
    register_schedule_handlers(application)
    register_plugin_handlers(application)
    register_mcp_handlers(application)

    if settings.enable_git:
        from keypal.channels.telegram.handlers.git import register_git_handlers

        register_git_handlers(application)

    register_message_handlers(application)  # Must be last (catches all text)
