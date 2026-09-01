#!/bin/bash
# Arbtr hook test harness
#
# 1. Graceful degradation: every hook exits 0 quietly, within budget,
#    when the server is unreachable.
# 2. Propose flow: session-end.sh proposes high-confidence candidates
#    through a local stub server when ARBTR_AGENT_KEY is set.
#
# Usage: bash test-hooks.sh

set -u
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

check() {
  local name="$1" ok="$2"
  if [[ "${ok}" == "0" ]]; then
    echo "PASS: ${name}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${name}"
    FAIL=$((FAIL + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"; [[ -n "${STUB_PID:-}" ]] && kill "${STUB_PID}" 2>/dev/null' EXIT

# A fake git repo with a commit and a touched file (durable evidence)
mkdir -p "${TMP}/repo"
(
  cd "${TMP}/repo"
  git init -q
  git config user.email t@t && git config user.name t
  echo hi > file.ts
  git add . && git commit -qm init
  git remote add origin https://example.com/org/repo.git
  echo more >> file.ts
)

# Fake transcript + hook input
TRANSCRIPT="${TMP}/transcript.jsonl"
echo '{"role":"user","content":"we decided to use pnpm"}' > "${TRANSCRIPT}"
HOOK_INPUT="{\"transcript_path\":\"${TRANSCRIPT}\",\"session_id\":\"sess-test\",\"tool_input\":{\"file_path\":\"${TMP}/repo/file.ts\",\"content\":\"import x from 'y'\"}}"

# ============================================================================
# 1. Graceful degradation: unreachable server, everything exits 0 fast
# ============================================================================
export ARBTR_API_URL="http://127.0.0.1:9"  # closed port
export ARBTR_API_KEY="mcp_arbtr_$(printf 'a%.0s' {1..32})"
export ARBTR_AGENT_KEY="arbtr_ak_$(printf 'a%.0s' {1..43})"

for hook in session-start.sh post-write.sh session-end.sh; do
  start=$(date +%s)
  ( cd "${TMP}/repo" && echo "${HOOK_INPUT}" | timeout 30 bash "${HOOKS_DIR}/${hook}" >/dev/null 2>&1 )
  code=$?
  took=$(( $(date +%s) - start ))
  [[ ${code} -eq 0 && ${took} -le 20 ]]; check "degradation: ${hook} exits 0 in ${took}s (unreachable server)" $?
done

# ============================================================================
# 2. Propose flow against a local stub
# ============================================================================
PORT=8973
python3 - "$PORT" > "${TMP}/stub.log" 2>&1 <<'PYEOF' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Stub(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        if self.path.endswith("/extract"):
            payload = {
                "decisions_found": 2,
                "review_url": "/test-team/decisions",
                "candidates": [
                    {"title": "Use pnpm for package management", "context": "c" * 210,
                     "positions": ["pnpm", "npm"], "arguments": ["faster installs"],
                     "tags": ["tooling"], "confidence": 90},
                    {"title": "Low confidence idea", "context": "c" * 210,
                     "confidence": 40},
                ],
            }
            code = 200
        elif self.path.endswith("/propose"):
            print("PROPOSE:" + json.dumps(body), flush=True)
            payload = {"decision": {"id": "d1", "slug": "use-pnpm"},
                       "idempotent": False,
                       "review_url": "/test-team/decisions?filter=proposed"}
            code = 201
        else:
            payload, code = {}, 404
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), Stub).serve_forever()
PYEOF
STUB_PID=$!
sleep 1

export ARBTR_API_URL="http://127.0.0.1:${PORT}/api/cli"
OUTPUT=$( cd "${TMP}/repo" && echo "${HOOK_INPUT}" | timeout 60 bash "${HOOKS_DIR}/session-end.sh" 2>&1 )
code=$?

[[ ${code} -eq 0 ]]; check "propose flow: session-end exits 0" $?
echo "${OUTPUT}" | grep -q "DECISIONS PROPOSED"; check "propose flow: reports proposals" $?
echo "${OUTPUT}" | grep -q "filter=proposed"; check "propose flow: shows queue URL" $?

PROPOSED=$(grep -c "^PROPOSE:" "${TMP}/stub.log" || true)
[[ "${PROPOSED}" -eq 1 ]]; check "propose flow: exactly the 1 high-confidence candidate proposed (got ${PROPOSED})" $?

grep "^PROPOSE:" "${TMP}/stub.log" | head -1 | grep -q '"idempotency_key": *"sess-test:0"'; check "propose flow: ordinal idempotency key" $?
grep "^PROPOSE:" "${TMP}/stub.log" | head -1 | grep -q 'commit '; check "propose flow: commit sha in evidence" $?
grep "^PROPOSE:" "${TMP}/stub.log" | head -1 | grep -q 'Positions considered'; check "propose flow: positions folded into context" $?

# ============================================================================
# 3. No agent key: falls back to URL behavior
# ============================================================================
unset ARBTR_AGENT_KEY
OUTPUT=$( cd "${TMP}/repo" && echo "${HOOK_INPUT}" | timeout 60 bash "${HOOKS_DIR}/session-end.sh" 2>&1 )
echo "${OUTPUT}" | grep -q "POTENTIAL DECISIONS DETECTED"; check "fallback: URL behavior without agent key" $?

echo ""
echo "${PASS} passed, ${FAIL} failed"
exit $(( FAIL > 0 ? 1 : 0 ))
