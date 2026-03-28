# Keypal

A confidant who knows you deeply and helps you unconditionally — always.

Keypal is an AI chatbot that communicates through Telegram, providing warm, thoughtful, and elegant conversations. It acts as a personal close friend and AI assistant that can build, deploy, schedule, and manage services autonomously.

## Tech Stack

- **Language**: Python 3.12+
- **Package Manager**: [uv](https://docs.astral.sh/uv/)
- **Telegram Integration**: [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot) (v22+, async, streaming via sendMessageDraft)
- **AI Backend**: [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview) — all messages routed through Claude with streaming, tool use, and plugins
- **Deployment**: Oracle Cloud Compute (VM, polling mode)

## Architecture

### Message Flow

```
Channel (Telegram, LINE, ...)
    │
    ▼
Auth Check (user whitelist via ALLOWED_USERS)
    │
    ▼
Channel-specific handlers (channels/<platform>/)
    ├── Commands      /start, /help, /services, /schedules, /plugins, /usage, /reset
    ├── Callbacks     Inline keyboard button actions
    └── Messages      Text, photos, documents
    │
    ▼
Service Layer (platform-agnostic)
    ├── MessageQueue       Per-user async queue (ordering + concurrency limit)
    └── ChatService        Claude Agent SDK (streaming, tool use, plugins, sessions)
        ├── on_draft       Streaming text → sendMessageDraft
        ├── on_status      Tool status → separate messages
        └── on_file        File output → send_photo / send_document
```

### Key Design Decisions

- **Multi-channel architecture**: Each messaging platform lives under `channels/<platform>/` with its own system prompt, chat service instance, and session prefix. Services are platform-agnostic.
- **Per-channel system prompts**: Each channel defines its own persona and capabilities in `channels/<platform>/prompt.py`.
- **Streaming responses**: Claude Agent SDK with `include_partial_messages=True` + Telegram `sendMessageDraft` for real-time text streaming.
- **Claude Agent SDK for everything**: All messages go through Claude with full Bash/file access. Plugins (ralph-loop, plugin-manager) loaded via SDK.
- **Immediate error recovery**: Services use `service-monitor.sh` (crash → Claude Code auto-repair), bot uses `guardian.sh`, scheduled tasks use `watchdog.sh --fix`.
- **Test before deploy**: System prompt requires testing prototypes and scheduled tasks before deployment.

## Project Structure

```
keypal/
├── Makefile                                 # setup, run, bg-run, stop, status, etc.
├── pyproject.toml
├── uv.lock
├── CLAUDE.md
├── .env.example
├── src/
│   └── keypal/
│       ├── __init__.py
│       ├── __main__.py                      # Entry point (argparse --channel)
│       ├── config.py                        # Settings (pydantic-settings, .env)
│       ├── channels/
│       │   └── telegram/
│       │       ├── __init__.py              # chat_service instance (TG-specific)
│       │       ├── prompt.py                # Telegram system prompt
│       │       ├── auth.py                  # User whitelist filter
│       │       ├── app.py                   # PTB Application + setMyCommands
│       │       └── handlers/
│       │           ├── __init__.py          # Register all handlers
│       │           ├── commands.py          # /start /help /reset /usage
│       │           ├── services.py          # /services + inline keyboard
│       │           ├── schedules.py         # /schedules + inline keyboard
│       │           ├── plugins.py           # /plugins + inline keyboard + pagination
│       │           └── messages.py          # Text, photo, document handlers + streaming
│       └── services/
│           ├── queue.py                     # Per-user async message queue
│           └── chat.py                      # ChatService (Agent SDK, streaming, usage tracking)
├── tests/
│
├── ~/.claude/scripts/                       # Operational scripts (JSON output)
│   ├── init.sh                              # Pre-flight checks + auto-fix
│   ├── cleanup.sh                           # Log rotation + upload cleanup (daily cron)
│   ├── healthcheck.sh                       # Service health check (manual)
│   ├── guardian.sh                          # Bot process guardian (auto-restart + auto-repair)
│   ├── service-monitor.sh                   # Service process monitor (crash → Claude Code fix)
│   ├── watchdog.sh                          # Task wrapper (failure → notify + diagnose + fix)
│   ├── deploy-prototype.sh                  # Deploy prototype via service-monitor
│   ├── stop-service.sh / clear-service.sh   # Service lifecycle
│   ├── list-services.sh                     # List running services
│   ├── create-schedule.sh                   # Create cron schedule
│   ├── pause/resume/update/clear-schedule.sh
│   ├── list-schedules.sh                    # List scheduled tasks
│   ├── install-plugin.sh / uninstall-plugin.sh
│   └── list-plugins.sh                      # Browse marketplace plugins
│
└── ~/.claude/plugins/local/plugin-manager/  # Custom plugin (loaded by Agent SDK)
    └── skills/
        ├── manage-plugins/SKILL.md          # Plugin discovery + install
        ├── prototype-deployer/SKILL.md      # Build + deploy + manage prototypes
        └── task-scheduler/SKILL.md          # Schedule + manage cron tasks
```

## Development

### Prerequisites

- Python 3.12+
- uv
- A Telegram Bot Token (from [@BotFather](https://t.me/BotFather))

### Setup

```bash
make setup          # Installs deps, Claude Code CLI, runs pre-flight checks
cp .env.example .env  # Fill in tokens
```

### Running

```bash
make run            # Foreground
make bg-run         # Background with guardian (auto-restart + auto-repair)
make stop           # Stop background bot
make status         # Check status
```

### Testing

```bash
make test
make lint
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TG_BOT_TOKEN` | Yes | — | Telegram bot token |
| `CLAUDE_MODEL` | No | `sonnet` | Claude model to use |
| `ALLOWED_TG_USERS` | No | — | Comma-separated Telegram user IDs (empty = allow all). First ID used for notifications. |
| `LOG_LEVEL` | No | `INFO` | Logging level |

## Conventions

- Use `async`/`await` everywhere — no blocking I/O in the event loop.
- Type hints on all function signatures.
- Use `pydantic-settings` for configuration; never hardcode secrets.
- Keep handlers thin: extract logic into services.
- Channel-specific code stays in `channels/<platform>/`, services are platform-agnostic.
- System prompts live in `channels/<platform>/prompt.py`.
- All operational scripts output JSON for programmatic consumption.
- Commit messages in English, imperative mood.
- Code comments in English.
