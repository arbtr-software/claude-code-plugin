---
description: Configure Arbtr API key
---

Help the user set up Arbtr:

1. Check if ARBTR_API_KEY is already set by running: `echo $ARBTR_API_KEY`

2. If not set, ask if they have an API key from Arbtr. If not, direct them to https://app.arbtr.ai/settings

3. Once they have the key, give them the command for their shell:
   - zsh: `echo 'export ARBTR_API_KEY=their_key' >> ~/.zshrc && source ~/.zshrc`
   - bash: `echo 'export ARBTR_API_KEY=their_key' >> ~/.bashrc && source ~/.bashrc`

4. Verify by running: `curl -s -H "Authorization: Bearer $ARBTR_API_KEY" https://app.arbtr.ai/api/cli/status | jq .`

5. If successful, tell them to restart Claude Code and they're good to go.
