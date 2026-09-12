#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" || ! -x /usr/bin/sandbox-exec ]]; then
  echo "The offline build check requires macOS with sandbox-exec and Swift 6 installed." >&2
  exit 1
fi

CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/actiontape-offline.XXXXXX")"
cleanup() {
  rm -rf -- "${CHECK_ROOT}"
}
trap cleanup EXIT

cd -- "${PROJECT_DIR}"
SWIFT_OPTIONS=(
  --scratch-path "${CHECK_ROOT}/build"
  --cache-path "${CHECK_ROOT}/cache"
  --config-path "${CHECK_ROOT}/config"
  --security-path "${CHECK_ROOT}/security"
  --disable-dependency-cache
  --disable-sandbox
)

# The outer sandbox denies network access for Swift and every child process.
# --disable-sandbox only disables SwiftPM's nested manifest/plugin sandbox;
# sandbox-exec cannot nest that sandbox inside this already-sandboxed process.
offline() {
  /usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' "$@"
}

echo "Building from vendored source with network access denied and empty SwiftPM caches."
offline swift build "${SWIFT_OPTIONS[@]}"
offline swift test "${SWIFT_OPTIONS[@]}"
BIN_DIR="$(offline swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"

# APFS commonly ignores filename case. Keep the Studio product name distinct
# from actiontape and prove a full package build did not overwrite the CLI.
CLI_VERSION="$(offline "${BIN_DIR}/actiontape" --version)"
if [[ "${CLI_VERSION}" != "0.1.0" ]]; then
  echo "Expected CLI version 0.1.0 after the full build; got: ${CLI_VERSION}" >&2
  exit 1
fi
offline "${BIN_DIR}/actiontape" --help
offline bash "${PROJECT_DIR}/scripts/test-cli.sh" "${BIN_DIR}/actiontape"

for TAPE in "${PROJECT_DIR}"/examples/*.yaml; do
  [[ -f "${TAPE}" ]] || continue
  offline "${BIN_DIR}/actiontape" validate "${TAPE}"
done

echo "Offline build, tests, and example format validation passed. No target apps were controlled."
