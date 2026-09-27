# Arbtr Plugin for Claude Code

Automatic architectural decision enforcement for AI-assisted development.

## What This Does

This plugin connects [Arbtr](https://arbtr.ai) to Claude Code, giving your AI coding assistant awareness of your team's architectural decisions.

**On session start:** Loads your team's active decisions into context. Claude knows your standards before writing any code.

**While coding:** Checks written code against decisions in real-time. Violations are flagged immediately so Claude can self-correct.

**On session end:** Analyzes the conversation for architectural choices. With an agent key, high-confidence choices are proposed to Arbtr automatically and wait in the acceptance queue for a teammate to accept or reject. Without one, they are listed as suggestions.

## Installation

```bash
# Add the Arbtr marketplace (one time)
/plugin marketplace add arbtr-software/claude-code-plugin

# Install the plugin
/plugin install arbtr
```

## Setup

Run `/arbtr:setup` in Claude Code, or do it by hand:

1. Open [Arbtr → Team settings → AI settings](https://arbtr.ai/teams/ai-settings), select your team, and in **Agent keys** create a key (type `claude-code`, a label such as `sam-laptop`). Copy it; it is shown only once.

2. Store the key in a file. Pick one:

```bash
# This repo only (run from the repo root; keep .arbtr/ in .gitignore)
mkdir -p .arbtr && printf 'ARBTR_AGENT_KEY=%s\n' 'your_key_here' > .arbtr/env && chmod 600 .arbtr/env

# All repos
mkdir -p ~/.config/arbtr && printf 'ARBTR_AGENT_KEY=%s\n' 'your_key_here' >> ~/.config/arbtr/env && chmod 600 ~/.config/arbtr/env
```

Do not put the agent key only in your shell profile: Claude Code removes credential variables before it runs the MCP headers helper, so the MCP tools see an agent key only when it is in one of these files.

3. Restart Claude Code

4. Verify it works — ask Claude: "What are our architecture decisions?"

Proposals also need the team's **agent writes** setting turned on (team owner or admin).

## What Gets Installed

| Component         | Purpose                                                   |
| ----------------- | --------------------------------------------------------- |
| MCP Server        | Query decisions, propose decisions, add comments          |
| SessionStart Hook | Load decisions into context automatically                 |
| PostToolUse Hook  | Check code against standards on every write               |
| Stop Hook         | Propose (or suggest) decisions found in the conversation  |
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

At the end of a session where architectural choices were made, Arbtr extracts them. With an agent key, up to three high-confidence choices are proposed automatically, with the repo, commit, and touched files attached as evidence:

```
=== ARBTR: DECISIONS PROPOSED ===

2 decision(s) proposed from this session, pending human
acceptance in Arbtr.
Review queue: https://arbtr.ai/acme/decisions?filter=proposed

=== END ===
```

Proposals are visible to the whole team and are labeled as unratified until a teammate accepts them. Without an agent key, the hook lists the choices as suggestions instead.

## Configuration

### Key files

Keys are read from, highest precedence first:

1. `<repo root>/.arbtr/env` — replaces the other two for this repo, so a key for one team never acts in a repo configured for another
2. environment variables (the hooks see all of them; the MCP tools see only a legacy `ARBTR_API_KEY`, never `ARBTR_AGENT_KEY`)
3. `~/.config/arbtr/env`

### Variables

| Variable          | Description                                   | Default                    |
| ----------------- | --------------------------------------------- | -------------------------- |
| `ARBTR_AGENT_KEY` | Your personal agent key (`arbtr_ak_...`)      | Required                   |
| `ARBTR_API_KEY`   | Legacy read-only team key (`mcp_arbtr_...`)   | Unset                      |
| `ARBTR_API_URL`   | CLI API base used by the hooks                | `https://arbtr.ai/api/cli` |
| `ARBTR_MCP_URL`   | MCP endpoint (shell variable only)            | `https://arbtr.ai/api/mcp` |
| `ARBTR_DEBUG`     | Enable debug logging                          | Unset                      |

When both keys are set, the agent key is used for everything: it carries your identity, so group-restricted decisions are filtered correctly.

## MCP Tools

The plugin includes an MCP server with these tools:

### Decisions & Standards

| Tool                  | Description                                       |
| --------------------- | ------------------------------------------------- |
| `search_decisions`    | Search decisions by keyword or topic              |
| `get_decision`        | Get full details of a specific decision           |
| `propose_decision`    | Propose a decision for teammates to accept (agent key) |
| `add_decision_comment`| Comment on an existing decision (agent key)       |
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

- Run `/arbtr:setup`; step 1 shows which key file applies and step 5 checks the key against the server
- Or by hand: `( source ~/.config/arbtr/env; curl -s -H "Authorization: Bearer $ARBTR_AGENT_KEY" https://arbtr.ai/api/cli/status )`
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

- A Claude Code version that supports `headersHelper` for MCP servers (tested with 2.1.283)
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
