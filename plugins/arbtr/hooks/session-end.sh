#!/bin/bash
# Arbtr Stop Hook
#
# Extracts potential architectural decisions from the session transcript.
# This script is called when a Claude Code session ends.
#
# Exit codes:
#   0 - Success (suggestions made or no decisions found)
#   1 - Error (shown to user)

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

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
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
  fi

  API_KEY="${ARBTR_API_KEY:-}"
  API_URL="${ARBTR_API_URL:-https://app.arbtr.ai/api/cli}"
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

  # Parse transcript path
  local transcript_path
  transcript_path=$(echo "${input}" | jq -r '.transcript_path // empty')

  if [[ -z "${transcript_path}" ]]; then
    log_debug "No transcript_path in input"
    exit 0
  fi

  if [[ ! -f "${transcript_path}" ]]; then
    log_debug "Transcript file not found: ${transcript_path}"
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

  log_debug "Analyzing transcript: ${transcript_path}"

  # Read transcript (limit to last 50KB for performance)
  local transcript
  transcript=$(tail -c 51200 "${transcript_path}" 2>/dev/null || cat "${transcript_path}")

  if [[ -z "${transcript}" ]]; then
    log_debug "Empty transcript"
    exit 0
  fi

  # Build request body
  local request_body
  request_body=$(jq -n --arg transcript "${transcript}" '{transcript: $transcript}')

  # Call extract API (longer timeout for AI processing)
  local response
  response=$(curl -sS --max-time 60 \
    -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${request_body}" \
    "${API_URL}/extract" 2>/dev/null)

  if [[ -z "${response}" ]]; then
    log_debug "No response from API"
    exit 0
  fi

  # Check for decisions found
  local decisions_found
  decisions_found=$(echo "${response}" | jq -r '.decisions_found // 0')

  if [[ "${decisions_found}" -gt 0 ]]; then
    local review_url
    review_url=$(echo "${response}" | jq -r '.review_url // ""')

    echo ""
    echo "=== ARBTR: POTENTIAL DECISIONS DETECTED ==="
    echo ""
    echo "The following architectural choices from this session might be worth"
    echo "recording as formal decisions in Arbtr:"
    echo ""

    # List candidates
    echo "${response}" | jq -r '.candidates[] | "- \(.title) (confidence: \(.confidence)%)"'

    echo ""
    echo "To record these decisions:"
    echo "  1. Go to Arbtr and create a new decision"
    echo "  2. Use Magic Paste to import the context"
    if [[ -n "${review_url}" ]]; then
      echo "  3. Or review at: https://arbtr.app${review_url}"
    fi
    echo ""
    echo "These suggestions are based on patterns in the conversation."
    echo "Not all may warrant formal decisions."
    echo ""
    echo "=== END SUGGESTIONS ==="
  else
    log_debug "No decisions detected in transcript"
  fi

  exit 0
}

main "$@"
