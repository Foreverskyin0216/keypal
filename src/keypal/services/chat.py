import contextlib
import logging
import time
from collections.abc import Callable, Coroutine
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    ResultMessage,
    StreamEvent,
    TextBlock,
)

from keypal.config import settings

logger = logging.getLogger(__name__)

CLAUDE_DIR = Path.home() / ".claude"
KEYPAL_DIR = Path.home() / ".keypal"
RALPH_LOOP_PLUGIN = CLAUDE_DIR / "plugins" / "marketplaces" / "claude-plugins-official" / "plugins" / "ralph-loop"
LOCAL_PLUGIN = CLAUDE_DIR / "plugins" / "local" / "plugin-manager"
MCP_REGISTRY = KEYPAL_DIR / "mcp.json"

# Minimum interval between draft updates (seconds)
DRAFT_UPDATE_INTERVAL = 0.4

DEFAULT_SYSTEM_PROMPT = "You are a helpful AI assistant."


@dataclass
class UsageStats:
    """Per-user token usage tracking."""

    total_cost_usd: float = 0.0
    message_count: int = 0

    def record(self, cost: float) -> None:
        self.total_cost_usd += cost
        self.message_count += 1


# Type aliases for callbacks
DraftCallback = Callable[[str], Coroutine[Any, Any, None]]
StatusCallback = Callable[[str], Coroutine[Any, Any, None]]
FileCallback = Callable[[str], Coroutine[Any, Any, None]]  # called with file path


def _tool_status(tool_name: str, tool_input_json: str = "") -> str:
    """Build a concise status line from tool name and partial input."""
    import json as _json
    import os

    hint = ""
    try:
        data = _json.loads(tool_input_json) if tool_input_json else {}
    except _json.JSONDecodeError:
        data = {}

    if tool_name in ("Read", "Write", "Edit"):
        path = data.get("file_path", "")
        hint = os.path.basename(path) if path else ""
    elif tool_name == "Bash":
        cmd = data.get("command", "")
        hint = cmd[:40].split("\n")[0] if cmd else ""
    elif tool_name in ("Grep", "Glob"):
        hint = data.get("pattern", "")[:30]
    elif tool_name == "WebSearch":
        hint = data.get("query", "")[:30]
    elif tool_name == "WebFetch":
        hint = data.get("url", "")[:40]

    labels = {
        "Read": "~ reading",
        "Write": "~ writing",
        "Edit": "~ editing",
        "Bash": "~ running",
        "Glob": "~ searching",
        "Grep": "~ searching",
        "WebSearch": "~ looking up",
        "WebFetch": "~ fetching",
        "Agent": "~ thinking",
        "Skill": "~ working",
    }
    label = labels.get(tool_name, f"~ {tool_name}")
    return f"{label} ... {hint}" if hint else f"{label} ..."


class ChatService:
    """Chat service powered by Claude Agent SDK with streaming support.

    Maintains a single ClaudeSDKClient with per-user sessions via session_id.
    Supports streaming responses via Telegram's sendMessageDraft.
    """

    def __init__(self, system_prompt: str = DEFAULT_SYSTEM_PROMPT, session_prefix: str = "default") -> None:
        self._system_prompt = system_prompt
        self._session_prefix = session_prefix
        self._client: ClaudeSDKClient | None = None
        self._session_epochs: dict[int, int] = {}  # user_id -> epoch counter
        self._usage: dict[int, UsageStats] = {}  # user_id -> usage stats

    @staticmethod
    def _discover_plugins() -> list[dict[str, str]]:
        plugins: list[dict[str, str]] = []
        for path in (RALPH_LOOP_PLUGIN, LOCAL_PLUGIN):
            if path.is_dir():
                plugins.append({"type": "local", "path": str(path)})
        return plugins

    @staticmethod
    def _load_mcp_servers() -> dict[str, Any]:
        """Load MCP server config from ~/.keypal/mcp.json."""
        import json

        if not MCP_REGISTRY.is_file():
            return {}
        try:
            with MCP_REGISTRY.open() as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return {}

    def _create_client(self) -> ClaudeSDKClient:
        mcp = self._load_mcp_servers()
        options = ClaudeAgentOptions(
            system_prompt=self._system_prompt,
            model=settings.claude_model,
            permission_mode="bypassPermissions",
            max_turns=30,
            plugins=self._discover_plugins(),
            include_partial_messages=True,
            **({"mcp_servers": mcp} if mcp else {}),
        )
        return ClaudeSDKClient(options=options)

    async def _ensure_client(self) -> ClaudeSDKClient:
        if self._client is None:
            self._client = self._create_client()
            await self._client.connect()
        return self._client

    async def _reconnect(self) -> ClaudeSDKClient:
        """Force reconnect on error."""
        if self._client is not None:
            with contextlib.suppress(Exception):
                await self._client.disconnect()
            self._client = None
        return await self._ensure_client()

    async def reply(
        self,
        user_id: int,
        message: str,
        on_draft: DraftCallback | None = None,
        on_status: StatusCallback | None = None,
        on_file: FileCallback | None = None,
    ) -> str:
        """Send a message and return Claude's text response.

        Args:
            user_id: Telegram user ID for session routing.
            message: User's message text.
            on_draft: Optional async callback for streaming text drafts.
            on_status: Optional async callback for tool status messages.
            on_file: Optional async callback when Claude writes a file the user should receive.
        """
        try:
            client = await self._ensure_client()
        except Exception:
            logger.warning("Client connection failed, reconnecting...")
            client = await self._reconnect()

        epoch = self._session_epochs.get(user_id, 0)
        session_id = f"{self._session_prefix}-{user_id}-{epoch}"

        try:
            await client.query(message, session_id=session_id)
        except Exception:
            logger.warning("Query failed, reconnecting and retrying...")
            client = await self._reconnect()
            await client.query(message, session_id=session_id)

        accumulated = ""
        last_draft_time = 0.0
        current_tool = ""
        tool_input_json = ""

        async for msg in client.receive_response():
            if isinstance(msg, StreamEvent):
                event = msg.event
                event_type = event.get("type", "")

                # Tool use started
                if event_type == "content_block_start":
                    content_block = event.get("content_block", {})
                    if content_block.get("type") == "tool_use":
                        current_tool = content_block.get("name", "")
                        tool_input_json = ""
                        # Send initial generic status (will update with details later)
                        if on_status:
                            with contextlib.suppress(Exception):
                                await on_status(_tool_status(current_tool))

                # Tool use finished — check if it wrote a file
                elif event_type == "content_block_stop":
                    if on_file and current_tool in ("Write", "Edit") and tool_input_json:
                        try:
                            import json as _json

                            tool_data = _json.loads(tool_input_json)
                            file_path = tool_data.get("file_path", "")
                            if file_path:
                                await on_file(file_path)
                        except Exception:
                            pass
                    current_tool = ""
                    tool_input_json = ""

                # Streaming deltas (text + tool input)
                elif event_type == "content_block_delta":
                    delta = event.get("delta", {})
                    # Accumulate tool input JSON and update status with details
                    if delta.get("type") == "input_json_delta":
                        tool_input_json += delta.get("partial_json", "")
                        # Try to update status with richer info
                        if on_status and current_tool and len(tool_input_json) > 30:
                            partial = tool_input_json if tool_input_json.startswith("{") else "{" + tool_input_json
                            detail = _tool_status(current_tool, partial)
                            with contextlib.suppress(Exception):
                                await on_status(detail)
                    elif delta.get("type") == "text_delta":
                        text_chunk = delta.get("text", "")
                        accumulated += text_chunk

                        if on_draft and accumulated.strip():
                            now = time.monotonic()
                            if now - last_draft_time >= DRAFT_UPDATE_INTERVAL:
                                last_draft_time = now
                                try:
                                    await on_draft(accumulated)
                                except Exception:
                                    logger.debug("Draft update failed", exc_info=True)

            elif isinstance(msg, AssistantMessage):
                # Final complete message — use this as authoritative text
                parts: list[str] = []
                for block in msg.content:
                    if isinstance(block, TextBlock):
                        parts.append(block.text)
                final = "".join(parts).strip()
                if final:
                    accumulated = final

            elif isinstance(msg, ResultMessage):
                # Track token cost
                cost = getattr(msg, "total_cost_usd", 0.0) or 0.0
                if user_id not in self._usage:
                    self._usage[user_id] = UsageStats()
                self._usage[user_id].record(cost)

        return accumulated.strip() or "..."

    def get_usage(self, user_id: int) -> UsageStats:
        """Get usage stats for a user."""
        return self._usage.get(user_id, UsageStats())

    def reset_session(self, user_id: int) -> None:
        """Reset a user's session by incrementing the epoch counter."""
        self._session_epochs[user_id] = self._session_epochs.get(user_id, 0) + 1

    async def shutdown(self) -> None:
        if self._client is not None:
            await self._client.disconnect()
            self._client = None
