# Plugin Manager

Browse, explain, and install Claude Code plugins conversationally.

TRIGGER when:
1. The user explicitly asks about available plugins, extensions, or capabilities they can add, or wants to install/enable a plugin.
2. You are unsure how to handle a user request and it might be solvable by an existing plugin. Before giving up or saying "I can't do that", check the plugin list first — there might be a plugin that adds that capability. Run this check in parallel with any web search you might do.

## Available Scripts

- **List plugins**: `~/.claude/scripts/list-plugins.sh [marketplace] [--installed-only]`
- **Install plugin**: `~/.claude/scripts/install-plugin.sh <plugin-name> [marketplace] [scope]`
- **Uninstall plugin**: `~/.claude/scripts/uninstall-plugin.sh <plugin-name> [marketplace] [scope]`

## How to Respond

### When the user asks what plugins are available or what capabilities can be added:

1. Run `~/.claude/scripts/list-plugins.sh` to get the full JSON list.
2. Group plugins by `category` and summarize them conversationally in the user's language.
3. Highlight which ones are already `installed: true`.
4. Do not dump the raw list. Describe what each category can do conversationally. For example:
   - "You currently have ralph-loop installed. There are also some useful ones like..."
   - "Development tools: code-review can auto-review PRs, code-simplifier helps simplify code..."
   - "Database: Firebase, Neon, Supabase integrations..."
   - "Automation: Stagehand lets you control a browser with natural language..."

### When the user asks to uninstall/disable a plugin:

1. Confirm with the user before uninstalling. Example: "Remove code-review plugin? You'll lose auto PR review."
2. Only after confirmation: run `~/.claude/scripts/uninstall-plugin.sh <plugin-name>`.
3. Remind the user to run `/reload-plugins` or restart the session.

### When the user asks to install a plugin:

1. Explain what the plugin does and ask for confirmation. Example: "code-review can auto-review your PRs. Install it?"
2. Only after confirmation: run `~/.claude/scripts/install-plugin.sh <plugin-name>`.
3. Remind the user to run `/reload-plugins` or restart the session to activate.

### When the user asks about a specific capability (e.g. "I need browser automation"):

1. Run `~/.claude/scripts/list-plugins.sh` to get the list.
2. Find plugins whose `description` or `category` matches the user's need.
3. Recommend the best match with a brief explanation of what it does.
4. Ask if they would like to install it.

### When you are unsure how to handle a user request:

1. Run `~/.claude/scripts/list-plugins.sh` in parallel with any web search.
2. Scan plugin names and descriptions for matches to the user's intent.
3. If a relevant plugin exists, suggest it to the user with a brief explanation and offer to install it.
4. If no plugin matches, proceed with your normal approach (web search, manual implementation, etc.).

## Style Guidelines

- Respond in the same language the user uses.
- Be conversational and helpful, not robotic.
- Group and summarize rather than listing every single plugin.
- If there are too many plugins in a category, highlight the top 2-3 most useful ones.
