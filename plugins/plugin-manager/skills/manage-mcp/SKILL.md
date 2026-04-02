# MCP Server Manager

Install, list, and remove MCP (Model Context Protocol) servers to extend capabilities.

TRIGGER when: the user wants to add new capabilities like browser automation, calendar, email, database access, or any external tool integration. Also trigger when the user asks about MCP servers, wants to list installed ones, or remove one.

## Available Scripts

- **Install**: `~/.claude/scripts/install-mcp.sh <name> <command> [args...]`
- **List**: `~/.claude/scripts/list-mcp.sh`
- **Uninstall**: `~/.claude/scripts/uninstall-mcp.sh <name>`

IMPORTANT: ONLY use these scripts to manage MCP servers. NEVER use `claude mcp add` or modify `~/.claude/settings.json` directly — the bot reads from `~/.keypal/mcp.json` exclusively.

## Common MCP Servers

When the user asks for a capability, suggest and install the appropriate MCP server:

| Capability | Name | Install Command |
|-----------|------|-----------------|
| Browser automation | browser | `install-mcp.sh browser npx @anthropic-ai/mcp-browser` |
| File system access | filesystem | `install-mcp.sh filesystem npx @anthropic-ai/mcp-filesystem ~/` |
| Web fetch | fetch | `install-mcp.sh fetch npx @anthropic-ai/mcp-fetch` |
| Google Calendar | google-calendar | `install-mcp.sh google-calendar npx @anthropic-ai/mcp-google-calendar` |
| GitHub | github | `install-mcp.sh github npx @anthropic-ai/mcp-github` |
| Slack | slack | `install-mcp.sh slack npx @anthropic-ai/mcp-slack` |
| PostgreSQL | postgres | `install-mcp.sh postgres npx @anthropic-ai/mcp-postgres` |
| SQLite | sqlite | `install-mcp.sh sqlite npx @anthropic-ai/mcp-sqlite` |

For other MCP servers, use WebSearch to find the right package. Search npm for `@anthropic-ai/mcp-*` or `@modelcontextprotocol/*`, or search the web for "MCP server <capability>".

## Known Dependencies

Some MCP servers require extra downloads beyond the npm package itself. The install script handles these automatically, but ALWAYS tell the user what's happening:

| MCP | Extra Dependency | What to tell the user |
|-----|-----------------|----------------------|
| browser / playwright | Chromium (~200MB) | "This will also download Chromium for browser automation. It may take a minute." |
| google-calendar | OAuth setup | "You'll need to set up Google OAuth credentials." |
| github | GitHub token | "You'll need a GitHub personal access token (GITHUB_TOKEN)." |
| slack | Slack token | "You'll need a Slack bot token (SLACK_BOT_TOKEN)." |
| postgres / sqlite | Database access | "Make sure the database is accessible from this machine." |

## Workflow

### Installing an MCP server:
1. Explain what the MCP server does and mention any extra dependencies (see table above).
   Example: "I found a browser MCP server for web automation. It'll also need to download Chromium (~200MB). Shall I install it?"
2. Only after the user confirms: run `install-mcp.sh <name> <command> [args...]`
   - The script pre-downloads npm packages and known dependencies automatically.
   - Check the `warmup` field in the JSON output to see what was pre-installed.
3. **Verify the install**: run `list-mcp.sh` and confirm the new MCP appears in the list.
   - If it doesn't appear, something went wrong — check `~/.keypal/mcp.json` directly.
4. Tell the user: "Installed and verified! Restart the bot or use /reset for it to take effect."
5. Report what was pre-installed (from the warmup field) so the user knows nothing will surprise them later.

### Listing MCP servers:
1. Run `list-mcp.sh` to get JSON array
2. Present conversationally: name, what it does

### Removing an MCP server:
1. Confirm with the user before removing. Example: "Remove the browser MCP server? You'll lose web automation."
2. Only after confirmation: run `uninstall-mcp.sh <name>`

## Important Notes

- MCP servers are registered in `~/.keypal/mcp.json` — this is the ONLY registry the bot reads.
- Changes require bot restart to take effect (MCP servers are loaded at client creation time).
- Some MCP servers need environment variables (API keys) — add them to `~/.keypal/.env` or the system `.env`.
- The bot loads all registered MCP servers automatically via `ChatService`.
- Always be transparent about what's being downloaded and how long it might take.

## Style

- Respond in the user's language.
- When suggesting MCP servers, explain what capability it adds in simple terms.
