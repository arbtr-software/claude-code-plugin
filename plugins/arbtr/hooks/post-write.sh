#!/bin/bash
# Arbtr PostToolUse Hook
#
# Validates written code against architectural decisions after Edit/Write operations.
# This script receives tool execution info on stdin and returns violations.
#
# Features:
# - Checks code against team standards (blocking if violations found)
# - Auto-detects and logs new dependencies (fire-and-forget, non-blocking)
#
# Exit codes:
#   0 - No violations or graceful degradation
#   2 - Blocking violation (Claude should fix)

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_FILE="${HOME}/.config/arbtr/env"
API_URL="${ARBTR_API_URL:-https://arbtr.com/api/cli}"

# File extensions to check for standards violations
CHECKABLE_EXTENSIONS="ts tsx js jsx py go rs java rb php"

# File extensions for import detection (JS/TS only for now)
IMPORT_DETECTION_EXTENSIONS="ts tsx js jsx mjs cjs mts cts"

# Directory containing this script (for finding helper scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_debug() {
  if [[ -n "${ARBTR_DEBUG:-}" ]]; then
    echo "[arbtr] DEBUG: $1" >&2
  fi
}

# Log errors to a persistent file for debugging background processes
# Errors are stored at ~/.arbtr/import-detect.log
log_error_to_file() {
  local log_file="${HOME}/.arbtr/import-detect.log"
  local max_lines=1000
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Ensure directory exists
  mkdir -p "$(dirname "${log_file}")"

  # Append error with timestamp
  echo "[${timestamp}] ${message}" >> "${log_file}"

  # Rotate log if it gets too long (keep last 1000 lines)
  if [[ -f "${log_file}" ]] && [[ $(wc -l < "${log_file}") -gt ${max_lines} ]]; then
    tail -n ${max_lines} "${log_file}" > "${log_file}.tmp" && mv "${log_file}.tmp" "${log_file}"
  fi
}

# Load configuration
load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
  fi

  API_KEY="${ARBTR_API_KEY:-}"
  API_URL="${ARBTR_API_URL:-https://arbtr.com/api/cli}"
}

# Check if file extension is checkable for standards
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

# Check if file extension supports import detection
supports_import_detection() {
  local file_path="$1"
  local extension="${file_path##*.}"

  for ext in ${IMPORT_DETECTION_EXTENSIONS}; do
    if [[ "${extension}" == "${ext}" ]]; then
      return 0
    fi
  done
  return 1
}

# Detect and log new imports (fire-and-forget)
# This runs in background to avoid blocking the developer flow
detect_and_log_imports() {
  local file_path="$1"
  local content="$2"

  # Skip if file doesn't support import detection
  if ! supports_import_detection "${file_path}"; then
    log_debug "File type not supported for import detection: ${file_path}"
    return 0
  fi

  # Skip if no content
  if [[ -z "${content}" ]]; then
    log_debug "No content for import detection"
    return 0
  fi

  # Check if Node.js is available
  if ! command -v node &>/dev/null; then
    log_debug "Node.js not available for import detection"
    return 0
  fi

  # Check if the helper script exists
  local helper_script="${SCRIPT_DIR}/detect-imports.mjs"
  if [[ ! -f "${helper_script}" ]]; then
    log_debug "Import detection helper not found: ${helper_script}"
    return 0
  fi

  # Run import detection in background (fire-and-forget)
  # Logs errors to ~/.arbtr/import-detect.log for debugging
  (
    local exit_code=0
    local output
    output=$(node "${helper_script}" "${file_path}" "${content}" "${API_URL}" "${API_KEY}" 2>&1) || exit_code=$?

    # Log output for debugging (stderr only when debug enabled)
    if [[ -n "${output}" ]]; then
      echo "${output}" | while IFS= read -r line; do
        log_debug "[import-detect] ${line}"
      done
    fi

    # Log errors to persistent file for diagnosis
    if [[ ${exit_code} -ne 0 ]]; then
      log_error_to_file "FAILED (exit ${exit_code}) ${file_path}: ${output}"
    fi
  ) &

  log_debug "Started background import detection for ${file_path}"
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

  # ============================================================================
  # IMPORT DETECTION (fire-and-forget, runs in background)
  # ============================================================================

  # Start import detection in background - doesn't block the main flow
  # This auto-logs new dependencies to close the feedback loop
  detect_and_log_imports "${file_path}" "${content}"

  # ============================================================================
  # STANDARDS CHECK (blocking if violations found)
  # ============================================================================

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
