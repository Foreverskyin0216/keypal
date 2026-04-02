import asyncio
import contextlib
import logging
import re
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
from claude_agent_sdk.types import HookMatcher, SyncHookJSONOutput

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

# --- Dangerous command detection ---
LOG_DIR = Path.home() / "logs" / "keypal"
DANGER_LOG = LOG_DIR / "dangerous-commands.log"
AUDIT_LOG = LOG_DIR / "command-audit.log"

DANGEROUS_PATTERNS = [
    (re.compile(r"\brm\s+(-\S+\s+)*-\S*r"), "recursive delete (rm -r)"),
    (re.compile(r"\bshred\b"), "shred"),
    (re.compile(r"\bdd\s+if="), "disk write (dd)"),
    (re.compile(r"\bmkfs\b"), "filesystem format (mkfs)"),
    (re.compile(r"\bfdisk\b"), "disk partition (fdisk)"),
    (re.compile(r"\bparted\b"), "disk partition (parted)"),
    (re.compile(r">\s*/dev/"), "device write"),
    (re.compile(r"\bchmod\s+(-[^\s]*)?\s*-R\s+(777|000)\b"), "broad permission change"),
    (re.compile(r"\bchown\s+(-[^\s]*)?\s*-R\b"), "recursive ownership change"),
    (re.compile(r"\bkillall\b"), "killall"),
    (re.compile(r"\bpkill\b"), "pkill"),
    (re.compile(r"\breboot\b"), "reboot"),
    (re.compile(r"\bshutdown\b"), "shutdown"),
    (re.compile(r"\bhalt\b"), "halt"),
    (re.compile(r"\binit\s+[06]\b"), "init runlevel change"),
    (re.compile(r"\biptables\s+-F\b"), "firewall flush"),
    (re.compile(r"\bufw\s+disable\b"), "firewall disable"),
    (re.compile(r"(curl|wget)\s+.*\|\s*(ba)?sh"), "remote code execution (curl|sh)"),
    (re.compile(r"\bDROP\s+(DATABASE|TABLE)\b", re.IGNORECASE), "DROP DATABASE/TABLE"),
    (re.compile(r"\bTRUNCATE\b", re.IGNORECASE), "TRUNCATE"),
    (re.compile(r"\bgit\s+push\s+--force\b"), "git force push"),
    (re.compile(r"\bgit\s+reset\s+--hard\b"), "git reset --hard"),
]


def _check_dangerous(command: str) -> str | None:
    """Return a danger label if the command matches any dangerous pattern, else None."""
    for pattern, label in DANGEROUS_PATTERNS:
        if pattern.search(command):
            return label
    return None


def _audit_log(command: str, danger: str | None = None) -> None:
    """Append a Bash command to the audit log (and danger log if flagged)."""
    from datetime import UTC, datetime

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    # Collapse to single line for log readability
    cmd_oneline = command.replace("\n", " \\ ")[:500]

    with AUDIT_LOG.open("a") as f:
        f.write(f"{ts} {cmd_oneline}\n")

    if danger:
        with DANGER_LOG.open("a") as f:
            f.write(f"{ts} [{danger}] {cmd_oneline}\n")


# --- Pre-execution approval gate ---
# Callback type: (approval_id, command_preview, danger_label) -> None
ApprovalSender = Callable[[str, str, str], Coroutine[Any, Any, None]]

APPROVAL_TIMEOUT = 60  # seconds to wait for user response


class DangerGate:
    """Pre-execution approval gate for dangerous commands.

    When a dangerous Bash command is detected by the PreToolUse hook,
    the gate sends an inline keyboard to Telegram and waits for the
    user to Allow or Deny before the command executes.
    """

    def __init__(self) -> None:
        self._senders: dict[int, ApprovalSender] = {}  # user_id -> send keyboard fn
        self._pending: dict[str, asyncio.Future[bool]] = {}  # approval_id -> future

    def set_sender(self, user_id: int, sender: ApprovalSender) -> None:
        """Register the keyboard sender for a user (set before each reply)."""
        self._senders[user_id] = sender

    def clear_sender(self, user_id: int) -> None:
        """Unregister the sender after reply completes."""
        self._senders.pop(user_id, None)

    async def check(self, user_id: int, approval_id: str, command: str, label: str) -> bool:
        """Send approval keyboard and wait for user response. Returns True to allow."""
        sender = self._senders.get(user_id)
        if not sender:
            return True  # No sender = non-interactive context, allow

        loop = asyncio.get_running_loop()
        future: asyncio.Future[bool] = loop.create_future()
        self._pending[approval_id] = future

        try:
            await sender(approval_id, command, label)
            return await asyncio.wait_for(future, timeout=APPROVAL_TIMEOUT)
        except TimeoutError:
            logger.info("Danger approval timed out for %s (user %d)", label, user_id)
            return False  # Timeout = deny
        except Exception:
            logger.warning("Danger approval failed", exc_info=True)
            return False
        finally:
            self._pending.pop(approval_id, None)

    def resolve(self, approval_id: str, allow: bool) -> bool:
        """Resolve a pending approval (called by Telegram callback handler)."""
        future = self._pending.get(approval_id)
        if future and not future.done():
            future.set_result(allow)
            return True
        return False


# Module-level singleton — shared between ChatService and Telegram handlers
danger_gate = DangerGate()


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
KeepAliveCallback = Callable[[], Coroutine[Any, Any, None]]  # periodic typing indicator


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

    def _extract_user_id(self, session_id: str) -> int | None:
        """Extract user_id from session_id format: {prefix}-{user_id}-{epoch}."""
        parts = session_id.rsplit("-", 2)
        if len(parts) >= 3:
            try:
                return int(parts[-2])
            except ValueError:
                pass
        return None

    async def _pre_tool_hook(
        self,
        hook_input: dict[str, Any],
        _matcher: str | None,
        _context: Any,
    ) -> SyncHookJSONOutput:
        """PreToolUse hook: intercept dangerous Bash commands before execution."""
        tool_input = hook_input.get("tool_input", {})
        cmd = tool_input.get("command", "")
        if not cmd:
            return {}

        danger = _check_dangerous(cmd)
        if not danger:
            return {}

        # Extract user from session_id
        session_id = hook_input.get("session_id", "")
        user_id = self._extract_user_id(session_id)
        if user_id is None:
            return {}

        approval_id = hook_input.get("tool_use_id", "")
        allowed = await danger_gate.check(user_id, approval_id, cmd, danger)

        _audit_log(cmd, danger)

        if allowed:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                }
            }
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"User denied: {danger}",
            }
        }

    def _create_client(self) -> ClaudeSDKClient:
        mcp = self._load_mcp_servers()
        options = ClaudeAgentOptions(
            system_prompt=self._system_prompt,
            model=settings.claude_model,
            permission_mode="bypassPermissions",
            max_turns=300,
            plugins=self._discover_plugins(),
            include_partial_messages=True,
            hooks={
                "PreToolUse": [
                    HookMatcher(
                        matcher="Bash",
                        hooks=[self._pre_tool_hook],
                        timeout=APPROVAL_TIMEOUT + 10,
                    )
                ]
            },
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
        on_keepalive: KeepAliveCallback | None = None,
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
        last_keepalive_time = 0.0
        current_tool = ""
        tool_input_json = ""

        async for msg in client.receive_response():
            if on_keepalive:
                now = time.monotonic()
                if now - last_keepalive_time >= 4.0:
                    last_keepalive_time = now
                    with contextlib.suppress(Exception):
                        await on_keepalive()

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

                # Tool use finished — check if it wrote a file or ran a dangerous command
                elif event_type == "content_block_stop":
                    if current_tool in ("Write", "Edit") and tool_input_json and on_file:
                        try:
                            import json as _json

                            tool_data = _json.loads(tool_input_json)
                            file_path = tool_data.get("file_path", "")
                            if file_path:
                                await on_file(file_path)
                        except Exception:
                            pass

                    if current_tool == "Bash" and tool_input_json:
                        try:
                            import json as _json

                            tool_data = _json.loads(tool_input_json)
                            cmd = tool_data.get("command", "")
                            if cmd:
                                _audit_log(cmd)
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

        import re

        result = accumulated.strip()
        # Strip ralph-loop promise tags from output
        result = re.sub(r"<promise>.*?</promise>", "", result).strip()
        return result or "..."

    def get_usage(self, user_id: int) -> UsageStats:
        """Get usage stats for a user."""
        return self._usage.get(user_id, UsageStats())

    async def reset_session(self, user_id: int) -> None:
        """Reset a user's session — new epoch + reconnect client."""
        self._session_epochs[user_id] = self._session_epochs.get(user_id, 0) + 1
        # Reconnect to ensure clean state
        await self._reconnect()

    async def shutdown(self) -> None:
        if self._client is not None:
            await self._client.disconnect()
            self._client = None
