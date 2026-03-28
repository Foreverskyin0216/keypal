# Prototype Deployer

Build, deploy, and manage prototype web apps end-to-end.

TRIGGER when: the user asks you to build a website, web app, prototype, landing page, dashboard, or any hostable project. Also trigger when the user asks about running services, wants to stop/restart/delete a service, or check service status.

## Available Scripts

- **Deploy**: `~/.claude/scripts/deploy-prototype.sh <name> <dir> [port] [command]`
- **Stop**: `~/.claude/scripts/stop-service.sh <name>` — stop process only, keep files
- **Clear**: `~/.claude/scripts/clear-service.sh <name>` — stop + delete all files
- **Clear all**: `~/.claude/scripts/clear-service.sh --all` — stop all + delete everything
- **List**: `~/.claude/scripts/list-services.sh`
- **Watchdog**: `~/.claude/scripts/watchdog.sh --name <name> [--notify] [--diagnose] [--fix] <command...>` — wrap a service start command to auto-notify/diagnose on crash

All scripts output JSON for programmatic consumption.

## Workflow: Building and Deploying a Prototype

When the user describes what they want built:

1. **Choose a name** for the prototype (lowercase, hyphenated, e.g. `todo-app`).
2. **Create the project directory**: `~/prototypes/<name>/`
3. **Write all code files** needed for the project. Prefer simple, self-contained stacks:
   - Static sites: plain HTML/CSS/JS with `index.html`
   - Dynamic apps: Node.js (Express) or Python (Flask/FastAPI)
   - Install dependencies if needed (`npm install`, `pip install`)
4. **Deploy** by running: `~/.claude/scripts/deploy-prototype.sh <name> ~/prototypes/<name>/`
   - The script auto-detects the start command and assigns a port
   - You can override: `deploy-prototype.sh <name> <dir> <port> "<custom command>"`
5. **Parse the JSON output** and tell the user:
   - The URL where they can access it
   - A brief summary of what was built
   - Any next steps or known limitations

## Workflow: Managing Services

When the user asks about running services or wants to manage them:

1. Run `~/.claude/scripts/list-services.sh` to get current status.
2. Present results conversationally:
   - Which services are running vs stopped
   - Their URLs
   - Offer to stop, restart, or delete as needed
3. To stop (keep files): `~/.claude/scripts/stop-service.sh <name>`
4. To clear (stop + delete files): `~/.claude/scripts/clear-service.sh <name>`
5. To clear all: `~/.claude/scripts/clear-service.sh --all`
6. To restart: stop then re-deploy.

## Important Notes

- The deploy script uses `nohup` to run processes in the background.
- Logs are stored in `~/prototypes/logs/<name>.log` — read these if something goes wrong.
- The registry is at `~/prototypes/registry.json`.
- Port range: 3001-3099, auto-assigned if not specified.
- The deploy script sets the `PORT` environment variable for frameworks that read it.
- If auto-detection fails, specify the start command explicitly.
- Always verify deployment succeeded by checking the JSON output status field.

## Style

- Respond in the user's language.
- After deployment, always share the URL prominently.
- If something fails, read the log file and diagnose before reporting to the user.
