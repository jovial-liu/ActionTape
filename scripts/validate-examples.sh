#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

cd -- "${PROJECT_DIR}"
swift build --skip-update --product actiontape
BIN_DIR="$(swift build --skip-update --show-bin-path)"

FOUND=0
for TAPE in "${PROJECT_DIR}"/examples/*.yaml; do
  [[ -f "${TAPE}" ]] || continue
  FOUND=1
  echo "Validating ${TAPE#"${PROJECT_DIR}/"}"
  "${BIN_DIR}/actiontape" validate "${TAPE}"
done

if [[ "${FOUND}" -ne 1 ]]; then
  echo "No example tapes found in ${PROJECT_DIR}/examples" >&2
  exit 1
fi
