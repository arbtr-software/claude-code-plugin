#!/bin/bash
# Arbtr MCP headers helper
#
# Claude Code runs this (headersHelper in .mcp.json) to get the headers for
# the Arbtr MCP server. It resolves the key with the same rules as the hooks
# (see config.sh), so a per-repo .arbtr/env applies to MCP tools too.
#
# Prefers the personal agent key: the legacy team key can read but cannot
# call write tools such as propose_decision.
#
# Claude Code runs the helper in the plugin directory and removes
# credential-like variables (ARBTR_*_KEY) from its environment, so keys must
# be in .arbtr/env or ~/.config/arbtr/env. The project directory is the
# working directory of the Claude Code process, found by going up the
# process tree (helper -> sh -> claude).
#
# Prints a JSON object of headers on stdout. Prints {} when no key is set,
# so the server answers 401 instead of the helper failing.

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

pid_cwd() {
  if [[ -e "/proc/$1/cwd" ]]; then
    readlink "/proc/$1/cwd" 2>/dev/null
  elif command -v lsof &>/dev/null; then
    lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
  fi
}

project_dir() {
  local pid=$$ comm i
  for i in 1 2 3 4 5; do
    pid=$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')
    [[ -z "${pid}" || "${pid}" == "1" ]] && return
    comm=$(ps -o comm= -p "${pid}" 2>/dev/null)
    case "${comm##*/}" in
      claude|node) pid_cwd "${pid}"; return ;;
    esac
  done
}

dir=$(project_dir)
arbtr_load_config "${dir:-${HOME}}"

MCP_KEY="${AGENT_KEY:-${API_KEY}}"
if [[ -z "${MCP_KEY}" ]]; then
  echo '{}'
  exit 0
fi

printf '{"Authorization":"Bearer %s"}\n' "${MCP_KEY}"
