# MCP Server Manager

Install, list, and remove MCP (Model Context Protocol) servers to extend capabilities.

TRIGGER when: the user wants to add new capabilities like browser automation, calendar, email, database access, or any external tool integration. Also trigger when the user asks about MCP servers, wants to list installed ones, or remove one.

## Available Scripts

- **Install**: `~/.claude/scripts/install-mcp.sh <name> <command> [args...]`
- **List**: `~/.claude/scripts/list-mcp.sh`
- **Uninstall**: `~/.claude/scripts/uninstall-mcp.sh <name>`

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

## Workflow

### Installing an MCP server:
1. Explain what the MCP server does and ask for confirmation before installing.
   Example: "I found a browser MCP server that lets me automate web pages. Shall I install it?"
2. Only after the user confirms: run `install-mcp.sh <name> <command> [args...]`
3. If the npm package isn't installed yet, run `npm install -g <package>` first
4. Tell the user: "Installed! Restart the bot or use /reset for it to take effect."

### Listing MCP servers:
1. Run `list-mcp.sh` to get JSON array
2. Present conversationally: name, what it does

### Removing an MCP server:
1. Confirm with the user before removing. Example: "Remove the browser MCP server? You'll lose web automation."
2. Only after confirmation: run `uninstall-mcp.sh <name>`

## Important Notes

- MCP servers are registered in `~/.keypal/mcp.json`
- Changes require bot restart to take effect (MCP servers are loaded at client creation time)
- Some MCP servers need environment variables (API keys) — add them via `install-mcp.sh` env support or `.env`
- The bot loads all registered MCP servers automatically via `ChatService`

## Style

- Respond in the user's language.
- When suggesting MCP servers, explain what capability it adds in simple terms.
