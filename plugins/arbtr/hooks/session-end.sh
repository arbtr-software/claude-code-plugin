#!/bin/bash
# Arbtr Stop Hook
#
# Extracts potential architectural decisions from the session transcript.
# When an agent key (ARBTR_AGENT_KEY) is configured, high-confidence
# candidates are proposed directly via POST /api/cli/propose — attributed,
# linted, deduplicated, and landing as pending human acceptance. Without
# an agent key (or when evidence can't be built), falls back to printing
# candidates with a review URL.
#
# Budget: one total 55s deadline inside the 60s Stop timeout —
# extract <=40s, then <=5s per propose over at most 3 candidates.
#
# Exit codes:
#   0 - Success (proposals made, suggestions printed, or nothing found)

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_FILE="${HOME}/.config/arbtr/env"
DEFAULT_API_URL="https://arbtr.com/api/cli"

TOTAL_DEADLINE=55
EXTRACT_TIMEOUT=40
PROPOSE_TIMEOUT=5
MAX_PROPOSALS=3
CONFIDENCE_THRESHOLD=70

START_TIME=$(date +%s)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_debug() {
  if [[ -n "${ARBTR_DEBUG:-}" ]]; then
    echo "[arbtr] DEBUG: $1" >&2
  fi
}

elapsed() {
  echo $(( $(date +%s) - START_TIME ))
}

# Load configuration. Precedence for each value:
#   1. environment variable
#   2. repo-level .arbtr/env (so one global key never proposes repo B's
#      decisions into repo A's team)
#   3. global ~/.config/arbtr/env
load_config() {
  local env_api_key="${ARBTR_API_KEY:-}"
  local env_agent_key="${ARBTR_AGENT_KEY:-}"
  local env_api_url="${ARBTR_API_URL:-}"

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)

  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
  fi
  if [[ -n "${repo_root}" && -f "${repo_root}/.arbtr/env" ]]; then
    # shellcheck source=/dev/null
    source "${repo_root}/.arbtr/env" 2>/dev/null || true
  fi

  # Environment always wins
  [[ -n "${env_api_key}" ]] && ARBTR_API_KEY="${env_api_key}"
  [[ -n "${env_agent_key}" ]] && ARBTR_AGENT_KEY="${env_agent_key}"
  [[ -n "${env_api_url}" ]] && ARBTR_API_URL="${env_api_url}"

  API_KEY="${ARBTR_API_KEY:-}"
  AGENT_KEY="${ARBTR_AGENT_KEY:-}"
  API_URL="${ARBTR_API_URL:-${DEFAULT_API_URL}}"
}

# Durable evidence from the working tree: remote, HEAD sha, touched files.
# Prints a JSON array; prints "[]" when nothing durable exists.
build_evidence() {
  local remote sha files
  remote=$(git remote get-url origin 2>/dev/null || true)
  sha=$(git rev-parse --short=12 HEAD 2>/dev/null || true)
  files=$(git status --porcelain 2>/dev/null | awk '{print $NF}' | head -10)

  if [[ -z "${sha}" && -z "${files}" ]]; then
    echo "[]"
    return
  fi

  {
    [[ -n "${remote}" ]] && echo "${remote}"
    [[ -n "${sha}" ]] && echo "commit ${sha}"
    if [[ -n "${files}" ]]; then
      echo "${files}"
    fi
    [[ -n "${SESSION_ID}" ]] && echo "session ${SESSION_ID}"
  } | jq -R . | jq -s .
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
  local input
  input=$(cat)

  if [[ -z "${input}" ]]; then
    log_debug "No input received"
    exit 0
  fi

  if ! command -v jq &>/dev/null; then
    log_debug "jq not available"
    exit 0
  fi

  local transcript_path
  transcript_path=$(echo "${input}" | jq -r '.transcript_path // empty')
  SESSION_ID=$(echo "${input}" | jq -r '.session_id // empty')

  if [[ -z "${transcript_path}" || ! -f "${transcript_path}" ]]; then
    log_debug "No usable transcript_path in input"
    exit 0
  fi

  load_config

  if [[ -z "${API_KEY}" && -z "${AGENT_KEY}" ]]; then
    log_debug "No API key configured"
    exit 0
  fi
  # Reads (extract) accept either key type
  local read_key="${API_KEY:-${AGENT_KEY}}"

  if ! command -v curl &>/dev/null; then
    log_debug "curl not available"
    exit 0
  fi

  log_debug "Analyzing transcript: ${transcript_path}"

  local transcript
  transcript=$(tail -c 51200 "${transcript_path}" 2>/dev/null || cat "${transcript_path}")
  if [[ -z "${transcript}" ]]; then
    log_debug "Empty transcript"
    exit 0
  fi

  local request_body
  request_body=$(jq -n --arg transcript "${transcript}" '{transcript: $transcript}')

  local response
  response=$(curl -sS --max-time "${EXTRACT_TIMEOUT}" \
    -X POST \
    -H "Authorization: Bearer ${read_key}" \
    -H "Content-Type: application/json" \
    -d "${request_body}" \
    "${API_URL}/extract" 2>/dev/null)

  if [[ -z "${response}" ]]; then
    log_debug "No response from extract API"
    exit 0
  fi

  local decisions_found
  decisions_found=$(echo "${response}" | jq -r '.decisions_found // 0')
  if [[ "${decisions_found}" -eq 0 ]]; then
    log_debug "No decisions detected in transcript"
    exit 0
  fi

  local review_url
  review_url=$(echo "${response}" | jq -r '.review_url // ""')

  # ==========================================================================
  # Propose path: agent key + durable evidence + budget remaining
  # ==========================================================================
  local evidence
  evidence=$(build_evidence)

  if [[ -n "${AGENT_KEY}" && "${evidence}" != "[]" ]]; then
    local proposed=0 skipped=0 ordinal=0 queue_url=""
    local candidates
    candidates=$(echo "${response}" | jq -c '.candidates[]?' 2>/dev/null)

    while IFS= read -r candidate && [[ ${proposed} -lt ${MAX_PROPOSALS} ]]; do
      [[ -z "${candidate}" ]] && continue
      local this_ordinal=${ordinal}
      ordinal=$((ordinal + 1))

      if [[ $(elapsed) -ge $((TOTAL_DEADLINE - PROPOSE_TIMEOUT)) ]]; then
        log_debug "Deadline reached; stopping proposes"
        break
      fi

      local confidence
      confidence=$(echo "${candidate}" | jq -r '.confidence // 0' | cut -d. -f1)
      if [[ "${confidence}" -lt ${CONFIDENCE_THRESHOLD} ]]; then
        skipped=$((skipped + 1))
        continue
      fi

      # Fold extracted positions/arguments into the context text
      # (no positions write exists in v0)
      local propose_body
      propose_body=$(echo "${candidate}" | jq -c \
        --argjson evidence "${evidence}" \
        --arg session "${SESSION_ID}" \
        --arg ordinal "${this_ordinal}" \
        --arg repo "$(git remote get-url origin 2>/dev/null || true)" \
        '{
          title: .title,
          context: ([.context // ""]
            + (if ((.positions // []) | length) > 0
               then ["", "Positions considered:"] + [(.positions // [])[] | "- \(.)"]
               else [] end)
            + (if ((.arguments // []) | length) > 0
               then ["", "Arguments:"] + [(.arguments // [])[] | "- \(.)"]
               else [] end)
            | join("\n")),
          evidence: $evidence,
          tags: (.tags // []),
          repo: $repo,
          source: ("claude-code session " + $session),
          idempotency_key: ($session + ":" + $ordinal)
        }')

      local propose_response http_code
      propose_response=$(curl -sS --max-time "${PROPOSE_TIMEOUT}" \
        -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${AGENT_KEY}" \
        -H "Content-Type: application/json" \
        -d "${propose_body}" \
        "${API_URL}/propose" 2>/dev/null)
      http_code=$(echo "${propose_response}" | tail -1)
      propose_response=$(echo "${propose_response}" | sed '$d')

      case "${http_code}" in
        200|201)
          proposed=$((proposed + 1))
          [[ -z "${queue_url}" ]] && queue_url=$(echo "${propose_response}" | jq -r '.review_url // ""')
          log_debug "Proposed: $(echo "${candidate}" | jq -r '.title')"
          ;;
        409|422)
          # Duplicate or lint refusal: quiet skip, the record exists or
          # the candidate wasn't good enough — never re-present it
          skipped=$((skipped + 1))
          log_debug "Refused (${http_code}): $(echo "${propose_response}" | jq -r '.errors[0] // .error // ""')"
          ;;
        "")
          # Client timeout is not a server abort: the proposal may have
          # landed. Point at the queue, never re-present the candidate.
          queue_url="${queue_url:-/decisions?filter=proposed}"
          log_debug "Propose timed out; it may still have landed"
          break
          ;;
        *)
          skipped=$((skipped + 1))
          log_debug "Propose failed (${http_code})"
          ;;
      esac
    done <<< "${candidates}"

    if [[ ${proposed} -gt 0 || -n "${queue_url}" ]]; then
      echo ""
      echo "=== ARBTR: DECISIONS PROPOSED ==="
      echo ""
      if [[ ${proposed} -gt 0 ]]; then
        echo "${proposed} decision(s) proposed from this session, pending human"
        echo "acceptance in Arbtr."
      else
        echo "A propose call timed out — it may still have landed."
      fi
      if [[ -n "${queue_url}" ]]; then
        echo "Review queue: ${API_URL%/api/cli}${queue_url}"
      fi
      echo ""
      echo "=== END ==="
      exit 0
    fi
    # Nothing proposed (all below threshold/refused): fall through to URL
  fi

  # ==========================================================================
  # Fallback: print candidates with a review URL (no agent key, no durable
  # evidence, or nothing proposed)
  # ==========================================================================
  echo ""
  echo "=== ARBTR: POTENTIAL DECISIONS DETECTED ==="
  echo ""
  echo "The following architectural choices from this session might be worth"
  echo "recording as formal decisions in Arbtr:"
  echo ""
  echo "${response}" | jq -r '.candidates[] | "- \(.title) (confidence: \(.confidence)%)"'
  echo ""
  echo "To record these decisions:"
  echo "  1. Go to Arbtr and create a new decision"
  echo "  2. Use Magic Paste to import the context"
  if [[ -n "${review_url}" ]]; then
    echo "  3. Or review at: ${API_URL%/api/cli}${review_url}"
  fi
  echo ""
  echo "Tip: configure ARBTR_AGENT_KEY (env, .arbtr/env, or ~/.config/arbtr/env)"
  echo "and high-confidence candidates will be proposed automatically."
  echo ""
  echo "=== END SUGGESTIONS ==="

  exit 0
}

main "$@"
