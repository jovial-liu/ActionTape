#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${1:-${PROJECT_DIR}/dist}"
CONFIGURATION="${ACTIONTAPE_CONFIGURATION:-release}"
VERSION="${ACTIONTAPE_VERSION:-0.1.0}"
BUILD_NUMBER="${ACTIONTAPE_BUILD_NUMBER:-1}"
SWIFT_OPTIONS=(--skip-update -c "${CONFIGURATION}")
if [[ -n "${ACTIONTAPE_SCRATCH_PATH:-}" ]]; then
  SWIFT_OPTIONS+=(--scratch-path "${ACTIONTAPE_SCRATCH_PATH}")
fi

if (($# > 1)) || [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: bash ./scripts/package-practice-app.sh [output-directory]"
  echo "Default output: dist/ActionTape Practice.app"
  echo "Environment: ACTIONTAPE_CONFIGURATION, ACTIONTAPE_VERSION, ACTIONTAPE_BUILD_NUMBER, ACTIONTAPE_SCRATCH_PATH"
  if (($# > 1)); then exit 2; fi
  exit 0
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Practice app packaging requires macOS and a Swift 6 toolchain." >&2
  exit 1
fi
if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "ACTIONTAPE_CONFIGURATION must be debug or release." >&2
  exit 2
fi
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "${BUILD_NUMBER}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Use a numeric x.y.z ACTIONTAPE_VERSION and a numeric ACTIONTAPE_BUILD_NUMBER." >&2
  exit 2
fi
if [[ -z "${OUTPUT_DIR}" || "${OUTPUT_DIR}" == "/" ]]; then
  echo "Refusing unsafe output directory: '${OUTPUT_DIR}'" >&2
  exit 2
fi

mkdir -p -- "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd -- "${OUTPUT_DIR}" && pwd)"
FINAL_APP="${OUTPUT_DIR}/ActionTape Practice.app"
STAGING_ROOT="$(mktemp -d "${OUTPUT_DIR}/.actiontape-practice.XXXXXX")"
STAGING_APP="${STAGING_ROOT}/ActionTape Practice.app"
cleanup() {
  rm -rf -- "${STAGING_ROOT}"
}
trap cleanup EXIT

cd -- "${PROJECT_DIR}"
swift build "${SWIFT_OPTIONS[@]}" --product ActionTapePractice
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
mkdir -p -- "${STAGING_APP}/Contents/MacOS" "${STAGING_APP}/Contents/Resources/Licenses"
install -m 0755 "${BIN_DIR}/ActionTapePractice" "${STAGING_APP}/Contents/MacOS/ActionTapePractice"
install -m 0644 "${SCRIPT_DIR}/ActionTapePractice.Info.plist" "${STAGING_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${STAGING_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${STAGING_APP}/Contents/Info.plist"
install -m 0644 "${PROJECT_DIR}/LICENSE" "${STAGING_APP}/Contents/Resources/Licenses/ActionTape-LICENSE.txt"
bash "${SCRIPT_DIR}/create-app-icon.sh" "${PROJECT_DIR}/Sources/ActionTapeStudio/Resources/AppIcon.png" "${STAGING_APP}/Contents/Resources/ActionTape.icns"
swift "${SCRIPT_DIR}/verify-app.swift" "${STAGING_APP}"

if [[ -e "${FINAL_APP}" || -L "${FINAL_APP}" ]]; then
  BACKUP_ROOT="$(mktemp -d "${OUTPUT_DIR}/ActionTape-Practice-previous.XXXXXX")"
  mv -- "${FINAL_APP}" "${BACKUP_ROOT}/ActionTape Practice.app"
  echo "Preserved the previous bundle at ${BACKUP_ROOT}/ActionTape Practice.app"
fi
mv -- "${STAGING_APP}" "${FINAL_APP}"
echo "Created ${FINAL_APP}"
echo "Development bundle only: no Developer ID signature or notarization was added."
