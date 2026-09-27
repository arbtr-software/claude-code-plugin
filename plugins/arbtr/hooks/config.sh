#!/bin/bash
# Arbtr shared configuration loader.
#
# Sourced by every hook and by mcp-headers.sh so that all of them resolve
# the same key for the same repo.
#
# Sources, highest precedence first:
#   1. repo-level .arbtr/env
#   2. environment variables (ARBTR_AGENT_KEY, ARBTR_API_KEY, ARBTR_API_URL)
#   3. global ~/.config/arbtr/env
#
# A repo-level .arbtr/env replaces both global sources instead of merging
# with them. Shell variables are global too (set once in ~/.zshrc), so a key
# for team A must never read or propose on behalf of a repo that is
# configured for team B.
#
# After arbtr_load_config:
#   AGENT_KEY  personal agent key (arbtr_ak_*), may be empty
#   API_KEY    legacy team key (mcp_arbtr_*), may be empty
#   READ_KEY   key for read calls: the agent key when present (it carries the
#              user's identity, so group visibility applies), else the team key
#   API_URL    CLI API base, default https://arbtr.ai/api/cli

ARBTR_GLOBAL_CONFIG="${HOME}/.config/arbtr/env"
ARBTR_DEFAULT_API_URL="https://arbtr.ai/api/cli"

# Usage: arbtr_load_config [dir]   (dir defaults to the current directory)
arbtr_load_config() {
  local repo_root
  repo_root=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || true)

  if [[ -n "${repo_root}" && -f "${repo_root}/.arbtr/env" ]]; then
    unset ARBTR_API_KEY ARBTR_AGENT_KEY ARBTR_API_URL
    # shellcheck source=/dev/null
    source "${repo_root}/.arbtr/env" 2>/dev/null || true
  elif [[ -f "${ARBTR_GLOBAL_CONFIG}" ]]; then
    local env_api_key="${ARBTR_API_KEY:-}"
    local env_agent_key="${ARBTR_AGENT_KEY:-}"
    local env_api_url="${ARBTR_API_URL:-}"
    # shellcheck source=/dev/null
    source "${ARBTR_GLOBAL_CONFIG}" 2>/dev/null || true
    [[ -n "${env_api_key}" ]] && ARBTR_API_KEY="${env_api_key}"
    [[ -n "${env_agent_key}" ]] && ARBTR_AGENT_KEY="${env_agent_key}"
    [[ -n "${env_api_url}" ]] && ARBTR_API_URL="${env_api_url}"
  fi

  API_KEY="${ARBTR_API_KEY:-}"
  AGENT_KEY="${ARBTR_AGENT_KEY:-}"
  READ_KEY="${AGENT_KEY:-${API_KEY}}"
  API_URL="${ARBTR_API_URL:-${ARBTR_DEFAULT_API_URL}}"
}
