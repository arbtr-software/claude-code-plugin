#!/bin/bash
# Arbtr SessionStart Hook
#
# Loads active architectural decisions into Claude's context at session start.
# This script is called automatically when a Claude Code session begins.
#
# Exit codes:
#   0 - Success (context loaded or graceful degradation)
#   1 - Error (shown to user)

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CACHE_DIR="${HOME}/.cache/arbtr"
CACHE_TTL=300  # 5 minutes
CONFIG_FILE="${HOME}/.config/arbtr/env"
API_URL="${ARBTR_API_URL:-https://app.arbtr.ai/api/cli}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_debug() {
  if [[ -n "${ARBTR_DEBUG:-}" ]]; then
    echo "[arbtr] DEBUG: $1" >&2
  fi
}

# Load configuration
load_config() {
  # Load from config file if exists
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
  fi

  # Environment overrides config file
  API_KEY="${ARBTR_API_KEY:-}"
  API_URL="${ARBTR_API_URL:-https://app.arbtr.ai/api/cli}"
}

# Detect git remote URL
get_git_remote() {
  if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
    git remote get-url origin 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Get cache file path based on git remote
get_cache_file() {
  local git_remote="$1"
  local hash
  hash=$(echo -n "${git_remote}" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "default")
  echo "${CACHE_DIR}/context-${hash}.json"
}

# Check if cache is valid
is_cache_valid() {
  local cache_file="$1"

  if [[ ! -f "${cache_file}" ]]; then
    return 1
  fi

  # Check age
  local cache_age
  if [[ "$(uname)" == "Darwin" ]]; then
    cache_age=$(( $(date +%s) - $(stat -f %m "${cache_file}" 2>/dev/null || echo 0) ))
  else
    cache_age=$(( $(date +%s) - $(stat -c %Y "${cache_file}" 2>/dev/null || echo 0) ))
  fi

  if [[ ${cache_age} -gt ${CACHE_TTL} ]]; then
    return 1
  fi

  return 0
}

# Fetch context from API
fetch_context() {
  local git_remote="$1"
  local encoded_remote

  # URL encode the git remote
  encoded_remote=$(printf '%s' "${git_remote}" | jq -sRr @uri 2>/dev/null || echo "")

  curl -sS --max-time 5 \
    -H "Authorization: Bearer ${API_KEY}" \
    "${API_URL}/context?git_remote=${encoded_remote}" 2>/dev/null
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
  load_config

  # Graceful degradation if not configured
  if [[ -z "${API_KEY}" ]]; then
    log_debug "No ARBTR_API_KEY configured, skipping context load"
    echo "# Arbtr: Not configured. Set ARBTR_API_KEY to enable architectural governance."
    exit 0
  fi

  # Check for required tools
  if ! command -v curl &>/dev/null; then
    log_debug "curl not available"
    exit 0
  fi

  if ! command -v jq &>/dev/null; then
    log_debug "jq not available"
    exit 0
  fi

  # Get git remote
  local git_remote
  git_remote=$(get_git_remote)
  log_debug "Git remote: ${git_remote}"

  # Check cache
  local cache_file
  cache_file=$(get_cache_file "${git_remote}")
  local context

  if is_cache_valid "${cache_file}"; then
    log_debug "Using cached context"
    context=$(jq -r '.context // empty' "${cache_file}" 2>/dev/null)
  else
    log_debug "Fetching fresh context from API"
    local response
    response=$(fetch_context "${git_remote}")

    if [[ -n "${response}" ]]; then
      context=$(echo "${response}" | jq -r '.context // empty' 2>/dev/null)

      if [[ -n "${context}" ]]; then
        # Cache the response
        mkdir -p "${CACHE_DIR}"
        echo "${response}" > "${cache_file}"
      fi
    fi

    # Fallback to stale cache if API failed
    if [[ -z "${context}" ]] && [[ -f "${cache_file}" ]]; then
      log_debug "Using stale cache"
      context=$(jq -r '.context // empty' "${cache_file}" 2>/dev/null)
    fi
  fi

  # Output context for Claude
  if [[ -n "${context}" ]]; then
    echo "=== ARBTR ARCHITECTURAL CONTEXT ==="
    echo ""
    echo "${context}"
    echo ""
    echo "=== END ARBTR CONTEXT ==="
    echo ""
    echo "When making architectural changes, check these decisions first."
    echo "Use mcp__arbtr__search_decisions for detailed lookups."
  else
    echo "# Arbtr: Could not load architectural context."
  fi

  exit 0
}

main "$@"
