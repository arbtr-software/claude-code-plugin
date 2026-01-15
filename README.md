# Arbtr Plugin for Claude Code

Automatic architectural decision enforcement for AI-assisted development.

## What This Does

This plugin connects [Arbtr](https://arbtr.ai) to Claude Code, giving your AI coding assistant awareness of your team's architectural decisions.

**On session start:** Loads your team's active decisions into context. Claude knows your standards before writing any code.

**While coding:** Checks written code against decisions in real-time. Violations are flagged immediately so Claude can self-correct.

**On session end:** Analyzes the conversation for architectural choices that might be worth documenting. Suggests capturing them in Arbtr.

## Installation

```bash
# Add the Arbtr marketplace (one time)
/plugin marketplace add arbtr-software/claude-code-plugin

# Install the plugin
/plugin install arbtr
```

## Setup

1. Sign up at [arbtr.ai](https://arbtr.ai)
2. Create a team and add your first decisions
3. Get your API key from Settings → API
4. Configure the plugin:

```bash
mkdir -p ~/.config/arbtr
echo "ARBTR_API_KEY=your_key_here" > ~/.config/arbtr/env
```

Or set the environment variable directly:

```bash
export ARBTR_API_KEY=your_key_here
```

## What Gets Installed

| Component         | Purpose                                                   |
| ----------------- | --------------------------------------------------------- |
| MCP Server        | Query decisions, log choices, search standards            |
| SessionStart Hook | Load decisions into context automatically                 |
| PostToolUse Hook  | Check code against standards on every write               |
| Stop Hook         | Extract potential decisions from conversations            |
| Governance Skill  | Guides Claude to check Arbtr before architectural changes |

## How It Works

### Decisions as Context

When you start a Claude Code session in a repo connected to Arbtr, your active decisions are automatically loaded:

```
=== ARBTR ARCHITECTURAL CONTEXT ===

[DECISION: Use Supabase for database access]
[STATUS: Active]
[ENFORCE: block *.firebase*, *.prisma*]
[REASON: Real-time sync, built-in auth, team familiarity]

[DECISION: Use TypeScript for all new code]
[STATUS: Active]
[ENFORCE: block *.js in src/]
[REASON: Type safety, better tooling, team standard]

=== END ARBTR CONTEXT ===
```

Claude sees this before you even ask a question.

### Real-Time Enforcement

When Claude writes code that violates a decision, it gets immediate feedback:

```
=== ARBTR STANDARDS VIOLATION ===

File: src/services/db.ts

The code you just wrote may violate team architectural standards:

- [BLOCK] Import 'firebase' is not allowed. Decision: Use Supabase for database access.

Please review and correct the code to comply with team standards.

=== END VIOLATION ===
```

Claude then fixes the code automatically.

### Decision Capture

At the end of a session where architectural choices were made, Arbtr suggests capturing them:

```
=== ARBTR: POTENTIAL DECISIONS DETECTED ===

The following architectural choices from this session might be worth
recording as formal decisions in Arbtr:

- Use custom hooks for client state management (confidence: 85%)
- Implement API routes in app/api directory (confidence: 72%)

To record these decisions, go to Arbtr and use Magic Paste to import the context.

=== END SUGGESTIONS ===
```

## Configuration

### Environment Variables

| Variable        | Description          | Default                        |
| --------------- | -------------------- | ------------------------------ |
| `ARBTR_API_KEY` | Your Arbtr API key   | Required                       |
| `ARBTR_API_URL` | API endpoint         | `https://app.arbtr.ai/api/cli` |
| `ARBTR_DEBUG`   | Enable debug logging | Unset                          |

### Config File

Alternatively, create `~/.config/arbtr/env`:

```bash
ARBTR_API_KEY=your_key_here
ARBTR_API_URL=https://app.arbtr.ai/api/cli
```

## MCP Tools

The plugin includes an MCP server with these tools:

### Decisions & Standards

| Tool                  | Description                                       |
| --------------------- | ------------------------------------------------- |
| `search_decisions`    | Search decisions by keyword or topic              |
| `get_decision`        | Get full details of a specific decision           |
| `log_choice`          | Record an architectural choice made during coding |
| `get_project_context` | Get all decisions relevant to current repo        |
| `check_standards`     | Validate a proposed choice against team standards |

### Git Integration

| Tool                 | Description                               |
| -------------------- | ----------------------------------------- |
| `git_search_prs`     | Search pull requests by keyword or author |
| `git_get_pr_status`  | Check status of a specific PR             |
| `git_search_code`    | Search for code patterns across repos     |
| `git_get_file`       | Read a file from a repository             |
| `git_list_directory` | List files in a repository directory      |
| `git_list_repos`     | List accessible repositories              |

Use these directly in conversation:

> "Search Arbtr for our authentication decisions"
> "Log that we chose to use React Query for server state"
> "Check if using Redux aligns with our standards"

## Troubleshooting

**Plugin not loading decisions:**

- Check API key is set: `echo $ARBTR_API_KEY`
- Verify connectivity: `curl -H "Authorization: Bearer $ARBTR_API_KEY" https://app.arbtr.ai/api/cli/status`
- Check repo is connected in Arbtr dashboard

**Violations not triggering:**

- Ensure PostToolUse hook is enabled in `/plugin` manager
- Check file extension is in supported list (ts, tsx, js, jsx, py, go, rs, java, rb, php)

**Debug mode:**

```bash
export ARBTR_DEBUG=1
```

Then check stderr output during Claude Code sessions.

## Requirements

- Claude Code 1.0.50+
- `curl` and `jq` installed
- Arbtr account with API access

## Other AI Tools

This plugin is Claude Code specific. For other MCP-compatible tools (Cursor, Windsurf), you can use the MCP server directly:

```bash
# Add to your MCP configuration
npx @arbtr/mcp-server
```

You'll get the query/search functionality but not the automatic hooks.

## Links

- [Arbtr](https://arbtr.ai) — Decision tracking platform
- [Documentation](https://docs.arbtr.ai) — Full docs
- [MCP Server](https://www.npmjs.com/package/@arbtr/mcp-server) — Standalone MCP package

## License

MIT License — see [LICENSE](LICENSE) for details.

## Support

- Issues: [GitHub Issues](https://github.com/arbtr-software/claude-code-plugin/issues)
- Email: support@arbtr.ai
