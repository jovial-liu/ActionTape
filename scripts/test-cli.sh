#!/usr/bin/env bash
set -euo pipefail

# A real-process regression: a mock runner cannot detect signal-handler traps
# or a Studio binary overwriting the CLI on case-insensitive volumes.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CLI="${1:-${PROJECT_DIR}/.build/debug/actiontape}"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/actiontape-cli.XXXXXX")"
CHILD_PID=""
cleanup() {
  if [[ -n "${CHILD_PID}" ]]; then
    kill -TERM "${CHILD_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${CHECK_DIR}"
}
trap cleanup EXIT

"${CLI}" run "${PROJECT_DIR}/Tests/Fixtures/cli-cancellation.yaml" \
  --trace "${CHECK_DIR}/trace.json" >"${CHECK_DIR}/stdout.txt" 2>"${CHECK_DIR}/stderr.txt" &
CHILD_PID=$!
# Allow startup; the fixture remains in a harmless 30-second pause.
sleep 1
kill -INT "${CHILD_PID}"
set +e
wait "${CHILD_PID}"
STATUS=$?
set -e
CHILD_PID=""
if [[ "${STATUS}" != 130 ]]; then
  echo "Expected Ctrl-C exit 130, received ${STATUS}." >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract status raw -o - "${CHECK_DIR}/trace.json")" != cancelled || \
      "$(/usr/bin/plutil -extract steps.0.status raw -o - "${CHECK_DIR}/trace.json")" != cancelled || \
      "$(/usr/bin/plutil -extract steps.1.status raw -o - "${CHECK_DIR}/trace.json")" != skipped ]]; then
  echo "Cancellation trace must cancel the current step and skip the next." >&2
  exit 1
fi
if [[ "$(/usr/bin/stat -f %Lp "${CHECK_DIR}/trace.json")" != 600 ]]; then
  echo "Trace permissions must be private (0600)." >&2
  exit 1
fi
echo "CLI Ctrl-C, skipped steps, exit status, and private trace passed."
