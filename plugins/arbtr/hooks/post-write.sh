#!/bin/bash
# Arbtr PostToolUse Hook
#
# Validates written code against architectural decisions after Edit/Write operations.
# This script receives tool execution info on stdin and returns violations.
#
# Exit codes:
#   0 - No violations or graceful degradation
#   2 - Blocking violation (Claude should fix)

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_FILE="${HOME}/.config/arbtr/env"
API_URL="${ARBTR_API_URL:-https://app.arbtr.ai/api/cli}"

# File extensions to check
CHECKABLE_EXTENSIONS="ts tsx js jsx py go rs java rb php"

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
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
  fi

  API_KEY="${ARBTR_API_KEY:-}"
  API_URL="${ARBTR_API_URL:-https://app.arbtr.ai/api/cli}"
}

# Check if file extension is checkable
is_checkable_file() {
  local file_path="$1"
  local extension="${file_path##*.}"

  for ext in ${CHECKABLE_EXTENSIONS}; do
    if [[ "${extension}" == "${ext}" ]]; then
      return 0
    fi
  done
  return 1
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
  # Read input from stdin
  local input
  input=$(cat)

  if [[ -z "${input}" ]]; then
    log_debug "No input received"
    exit 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    log_debug "jq not available"
    exit 0
  fi

  # Parse tool info
  local tool_name file_path content
  tool_name=$(echo "${input}" | jq -r '.tool_name // empty')
  file_path=$(echo "${input}" | jq -r '.tool_input.file_path // .tool_input.path // empty')
  content=$(echo "${input}" | jq -r '.tool_input.content // empty')

  log_debug "Tool: ${tool_name}, File: ${file_path}"

  # Skip if not a write/edit operation
  if [[ "${tool_name}" != "Write" ]] && [[ "${tool_name}" != "Edit" ]]; then
    exit 0
  fi

  # Skip if no file path
  if [[ -z "${file_path}" ]]; then
    exit 0
  fi

  # Skip if file type not checkable
  if ! is_checkable_file "${file_path}"; then
    log_debug "File type not checkable: ${file_path}"
    exit 0
  fi

  load_config

  # Skip if not configured
  if [[ -z "${API_KEY}" ]]; then
    log_debug "No API key configured"
    exit 0
  fi

  # Check for curl
  if ! command -v curl &>/dev/null; then
    log_debug "curl not available"
    exit 0
  fi

  # Build request body
  local request_body
  request_body=$(jq -n \
    --arg file_path "${file_path}" \
    --arg content "${content}" \
    '{file_path: $file_path, content: $content}')

  # Call check API
  local response
  response=$(curl -sS --max-time 10 \
    -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${request_body}" \
    "${API_URL}/check" 2>/dev/null)

  if [[ -z "${response}" ]]; then
    log_debug "No response from API"
    exit 0
  fi

  # Check for violations
  local compliant violations_count
  compliant=$(echo "${response}" | jq -r '.compliant // true')
  violations_count=$(echo "${response}" | jq -r '.violations | length // 0')

  if [[ "${compliant}" == "false" ]] && [[ "${violations_count}" -gt 0 ]]; then
    echo ""
    echo "=== ARBTR STANDARDS VIOLATION ==="
    echo ""
    echo "File: ${file_path}"
    echo ""
    echo "The code you just wrote may violate team architectural standards:"
    echo ""

    # Output violations
    echo "${response}" | jq -r '.violations[] | "- [\(.severity | ascii_upcase)] \(.message)"'

    # Output warnings if any
    local warnings_count
    warnings_count=$(echo "${response}" | jq -r '.warnings | length // 0')
    if [[ "${warnings_count}" -gt 0 ]]; then
      echo ""
      echo "Warnings:"
      echo "${response}" | jq -r '.warnings[] | "- \(.message)"'
    fi

    # Output suggestions if any
    local suggestions
    suggestions=$(echo "${response}" | jq -r '.suggestions | join("; ")')
    if [[ -n "${suggestions}" ]] && [[ "${suggestions}" != "null" ]]; then
      echo ""
      echo "Suggestions: ${suggestions}"
    fi

    echo ""
    echo "Please review and correct the code to comply with team standards."
    echo "Use mcp__arbtr__search_decisions to find approved alternatives."
    echo ""
    echo "=== END VIOLATION ==="

    # Check if any blocking violations
    local blocking_count
    blocking_count=$(echo "${response}" | jq -r '[.violations[] | select(.severity == "block")] | length')

    if [[ "${blocking_count}" -gt 0 ]]; then
      exit 2  # Blocking - Claude should fix
    fi
  fi

  exit 0
}

main "$@"
