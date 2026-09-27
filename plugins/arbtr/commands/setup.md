---
description: Configure your Arbtr agent key
---

Help the user connect this Claude Code install to Arbtr with a personal **agent key**.

Background you need:

- An agent key (`arbtr_ak_...`) belongs to one person on one team. It can read decisions, and it can propose decisions and add comments, attributed to that person.
- The older team key (`mcp_arbtr_...`) can only read. Do not recommend it for new setups.
- The agent key must be stored in a file, not only in a shell profile. Claude Code removes credential variables before it runs the MCP headers helper, so an `ARBTR_AGENT_KEY` that exists only in `~/.zshrc` does not reach the Arbtr MCP tools. (A legacy `ARBTR_API_KEY` in the shell still works for reads.)
- Never print a key value back to the user, and never write a key into a file that git tracks.

Steps:

1. **Check the current configuration.** Run these commands. They show only whether a key is present, not its value:
   ```bash
   root=$(git rev-parse --show-toplevel 2>/dev/null)
   [ -n "$root" ] && [ -f "$root/.arbtr/env" ] && grep -oE '^(export )?ARBTR_[A-Z_]+=' "$root/.arbtr/env"
   [ -f ~/.config/arbtr/env ] && grep -oE '^(export )?ARBTR_[A-Z_]+=' ~/.config/arbtr/env
   ```
   If `ARBTR_AGENT_KEY` is already set in the file that applies (the repo file if it exists, otherwise the global file), go to step 5.

2. **Get a key.** Tell the user to open https://arbtr.ai/teams/ai-settings, select the team that this repo belongs to, and in **Agent keys**:
   - choose the agent type `claude-code`
   - enter a label that names the person and machine, for example `sam-laptop`
   - click **Create key** and copy it (it is shown only once)

3. **Choose where to store it.** Ask the user:
   - **This repo only** (recommended when the user works with more than one Arbtr team): `<repo root>/.arbtr/env`. A repo file replaces the global file and any shell variables for this repo.
   - **All repos**: `~/.config/arbtr/env`.

4. **Write the file.** Ask the user to run the command themselves with the `!` prefix, so the key does not pass through you. Give them the command for the location they chose, with `PASTE_KEY_HERE` as a placeholder:
   - This repo only (run from the repo root):
     ```bash
     ! mkdir -p .arbtr && printf 'ARBTR_AGENT_KEY=%s\n' 'PASTE_KEY_HERE' > .arbtr/env && chmod 600 .arbtr/env
     ```
     Then make sure `.arbtr/` is in the repo's `.gitignore`. If it is not, add it.
   - All repos:
     ```bash
     ! mkdir -p ~/.config/arbtr && printf 'ARBTR_AGENT_KEY=%s\n' 'PASTE_KEY_HERE' >> ~/.config/arbtr/env && chmod 600 ~/.config/arbtr/env
     ```

5. **Verify.** Run this. It reads the key from the file and prints only the team name:
   ```bash
   root=$(git rev-parse --show-toplevel 2>/dev/null); f="$root/.arbtr/env"; [ -n "$root" ] && [ -f "$f" ] || f=~/.config/arbtr/env
   ( source "$f"; curl -s -H "Authorization: Bearer $ARBTR_AGENT_KEY" https://arbtr.ai/api/cli/status | jq -r '.team.name // .error' )
   ```
   - A team name means the key works. Confirm that it is the team the user expects.
   - `Invalid or revoked API key` means the key was copied wrong or was revoked. Go back to step 2.

6. **Finish.** Tell the user to restart Claude Code so the MCP server picks up the key. Also tell them:
   - Proposals need the team setting **agent writes** turned on. A team owner or admin controls it. Without it, reads work and proposals fail.
   - Agent proposals are visible to the whole team and wait in the acceptance queue until a teammate accepts or rejects them.
