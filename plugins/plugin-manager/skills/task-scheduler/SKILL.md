# Task Scheduler

Create, manage, and clear scheduled tasks powered by crontab.

TRIGGER when: the user asks to schedule something, run something periodically, set up a recurring task, or manage existing scheduled tasks. Examples: "every morning check X", "remind me daily", "schedule a backup", "pause the price checker", "what schedules do I have".

## Available Scripts

- **Create**: `~/.claude/scripts/create-schedule.sh <name> <cron-expr> <script-path> [description]`
- **List**: `~/.claude/scripts/list-schedules.sh`
- **Pause**: `~/.claude/scripts/pause-schedule.sh <name>`
- **Resume**: `~/.claude/scripts/resume-schedule.sh <name>`
- **Update**: `~/.claude/scripts/update-schedule.sh <name> [--cron <expr>] [--script <path>] [--description <text>]`
- **Clear**: `~/.claude/scripts/clear-schedule.sh <name>` or `~/.claude/scripts/clear-schedule.sh --all`
- **Watchdog** (decorator): `~/.claude/scripts/watchdog.sh --name <name> [--notify] [--diagnose] [--fix] <command...>`

All scripts output JSON.

## Workflow: Creating a Scheduled Task

When the user describes something they want to happen on a schedule:

1. **Parse the intent**: understand what they want done and when.
2. **Choose a name** (lowercase, hyphenated, e.g. `check-github-pr`).
3. **Convert the schedule to a cron expression**:
   - "every morning at 9" → `0 9 * * *`
   - "every hour" → `0 * * * *`
   - "every Monday at 10am" → `0 10 * * 1`
   - "every 30 minutes" → `*/30 * * * *`
4. **Write the task script** to `~/schedules/<name>/task.sh`:
   - The script should do the actual work (API calls, checks, processing, etc.)
   - Make it self-contained — include all necessary commands
   - If the task needs to notify the user, use the Telegram Bot API:
     ```bash
     curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id=USER_CHAT_ID -d text="Your message here"
     ```
5. **Register**: `~/.claude/scripts/create-schedule.sh <name> "<cron>" ~/schedules/<name>/task.sh "<description>"`
6. **Confirm** to the user: what was scheduled, when it runs, what it does.

## Workflow: Updating a Task

When the user wants to change the schedule or content:

### Changing the schedule (time):
```bash
~/.claude/scripts/update-schedule.sh <name> --cron "new cron expression"
```

### Changing the content (what it does):
1. Rewrite `~/schedules/<name>/task.sh` with the new logic.
2. Run: `~/.claude/scripts/update-schedule.sh <name> --script ~/schedules/<name>/task.sh`

### Changing both:
1. Rewrite the script.
2. Run: `~/.claude/scripts/update-schedule.sh <name> --cron "<expr>" --script ~/schedules/<name>/task.sh`

## Workflow: Managing Tasks

- **List all**: `~/.claude/scripts/list-schedules.sh` — shows all tasks with live crontab status
- **Pause**: `~/.claude/scripts/pause-schedule.sh <name>` — temporarily disable without deleting
- **Resume**: `~/.claude/scripts/resume-schedule.sh <name>` — re-enable a paused task
- **Clear one**: `~/.claude/scripts/clear-schedule.sh <name>` — remove crontab entry + delete files
- **Clear all**: `~/.claude/scripts/clear-schedule.sh --all`

## Watchdog: Auto-Notify and Auto-Diagnose on Failure

The watchdog script wraps any command and monitors for failures. Zero cost when tasks succeed.

### How to use with scheduled tasks:

Instead of scheduling the task script directly, wrap it with watchdog:

```bash
# In task.sh, wrap the actual work:
#!/usr/bin/env bash
~/.claude/scripts/watchdog.sh --name check-pr --notify --diagnose \
  ~/schedules/check-pr/actual-work.sh
```

Or write the task script to call watchdog internally on critical sections.

### Watchdog options:
- `--name <name>` — task name for notifications
- `--notify` — send Telegram alert on failure (default: on)
- `--no-notify` — disable Telegram alert
- `--diagnose` — spawn one-shot Claude Code to diagnose the error
- `--fix` — diagnose + attempt to fix automatically
- `--chat-id <id>` — Telegram chat ID (default: KEYPAL_CHAT_ID env)

### Token cost model:
- Task succeeds → exit 0 → watchdog does nothing → **zero tokens**
- Task fails → exit non-zero → Telegram notification → **zero tokens** (just curl)
- Task fails + `--diagnose` → one-shot Claude Code query → **minimal tokens** (one query)
- Task fails + `--fix` → Claude Code diagnoses + applies fix → **moderate tokens**

### Environment required:
- `TG_BOT_TOKEN` — for Telegram notifications
- `KEYPAL_CHAT_ID` — user's Telegram chat ID
- `claude` CLI — for --diagnose/--fix (must be on PATH)

When creating scheduled tasks, **always wrap with watchdog --notify --fix** by default. This ensures failures are immediately detected, diagnosed, and auto-repaired by Claude Code.

## Important Notes

- Scripts run in a minimal cron environment — always use absolute paths.
- Logs are at `~/schedules/logs/<name>.log` — check these if a task seems broken.
- Registry is at `~/schedules/registry.json`.
- Task scripts are at `~/schedules/<name>/task.sh`.
- Cron tags use the format `# keypal:<name>` for identification.
- If the task needs environment variables (API keys, tokens), source them explicitly in the script or read from `~/.env`.

## Style

- Respond in the user's language.
- When creating a schedule, clearly state the cron expression and what it means in plain language.
- When listing, show status (active/paused), schedule in human-readable form, and description.
