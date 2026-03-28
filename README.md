# Keypal

A confidant who knows you deeply and helps you unconditionally — always.

Keypal is a personal AI assistant that lives in your favorite messaging app. Powered by Claude via the Agent SDK, it can hold conversations, build and deploy web apps, schedule tasks, manage plugins and MCP integrations, and fix its own errors — all from a chat interface.

## Features

- **Chat** — Warm, context-aware conversations with streaming responses
- **Build & Deploy** — Describe what you want, Keypal writes the code and deploys it
- **Scheduled Tasks** — Automate recurring jobs with natural language
- **Plugins & MCP** — Extend capabilities by installing plugins or MCP servers
- **Self-Healing** — Auto-restarts on crash, auto-diagnoses and fixes errors
- **Self-Extending** — Creates new scripts and skills on its own, tracked in git
- **File & Image Support** — Send files/images to Keypal, receive files back
- **Multi-Channel** — Pluggable architecture for adding messaging platforms

## Quick Start

```bash
git clone https://github.com/Foreverskyin0216/keypal.git
cd keypal
cp .env.example .env   # Fill in your tokens
make setup             # Install deps + Claude Code CLI + pre-flight checks
make run               # Start bot (foreground)
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TG_BOT_TOKEN` | Yes | — | Telegram bot token from [@BotFather](https://t.me/BotFather) |
| `CLAUDE_MODEL` | No | `sonnet` | Claude model to use |
| `ALLOWED_TG_USERS` | No | — | Comma-separated user IDs for access control (empty = allow all) |
| `ENABLE_GIT` | No | `false` | Enable `/git` command for commit/push management |
| `LOG_LEVEL` | No | `INFO` | Logging level |

## Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/services` | Manage hosted prototypes |
| `/schedules` | Manage scheduled tasks |
| `/plugins` | Browse & install plugins |
| `/mcp` | Manage MCP server integrations |
| `/git` | View pending commits & push (opt-in) |
| `/usage` | View token spending for current session |
| `/reset` | Start a fresh conversation |

## Makefile

```bash
make setup        # Install deps, Claude Code CLI, run pre-flight checks
make run          # Start bot (foreground)
make bg-run       # Start bot (background, with auto-restart + auto-repair)
make stop         # Stop background bot
make status       # Show running status
make healthcheck  # Run service healthcheck
make test         # Run tests
make lint         # Run linter
make clean        # Stop all services + clear all schedules
```

## Architecture

```
Messaging Platform (Telegram, LINE, ...)
  |
  v
Channel Layer (auth, handlers, platform-specific UI)
  |
  v
Service Layer (platform-agnostic)
  ├── MessageQueue    Per-user ordering + concurrency control
  └── ChatService     Claude Agent SDK (streaming, tools, MCP, plugins)
        |
        v
      Scripts & Skills (deploy, schedule, monitor, self-repair)
```

Each messaging platform gets its own channel module with a dedicated system prompt and chat service instance. Services are platform-agnostic — adding a new channel requires no changes to the service layer.

## Self-Healing

- **Prototypes** crash → immediate detection → notify user → Claude Code diagnoses and fixes → auto-restart
- **Scheduled tasks** fail → watchdog catches → Claude Code auto-repairs
- **Bot** crashes → guardian detects → Claude Code diagnoses → auto-restart

## Self-Extending

Scripts and skills live in the repo and are symlinked to `~/.claude/`. When the bot's Claude creates a new script or skill, it's written directly into the repo — tracked by git and portable across machines.

## Tech Stack

- Python 3.12+ / [uv](https://docs.astral.sh/uv/)
- [python-telegram-bot](https://github.com/python-telegram-bot/python-telegram-bot) v22+
- [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview)

## License

See [LICENSE](LICENSE).
