#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${1:-${PROJECT_DIR}/.build/artifacts}"
CONFIGURATION="${ACTIONTAPE_CONFIGURATION:-release}"
VERSION="${ACTIONTAPE_VERSION:-0.1.0}"
BUILD_NUMBER="${ACTIONTAPE_BUILD_NUMBER:-1}"
SWIFT_OPTIONS=(--skip-update -c "${CONFIGURATION}")
if [[ -n "${ACTIONTAPE_SCRATCH_PATH:-}" ]]; then
  SWIFT_OPTIONS+=(--scratch-path "${ACTIONTAPE_SCRATCH_PATH}")
fi

if (($# > 1)) || [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: ./scripts/package-app.sh [output-directory]"
  echo "Environment: ACTIONTAPE_CONFIGURATION, ACTIONTAPE_VERSION, ACTIONTAPE_BUILD_NUMBER, ACTIONTAPE_SCRATCH_PATH"
  if (($# > 1)); then exit 2; fi
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ActionTape app packaging requires macOS and a Swift 6 toolchain." >&2
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
FINAL_APP="${OUTPUT_DIR}/ActionTape.app"
# Stage on the destination volume, so the final move does not become a copy.
STAGING_ROOT="$(mktemp -d "${OUTPUT_DIR}/.actiontape-package.XXXXXX")"
STAGING_APP="${STAGING_ROOT}/ActionTape.app"

cleanup() {
  rm -rf -- "${STAGING_ROOT}"
}
trap cleanup EXIT

cd -- "${PROJECT_DIR}"
swift build "${SWIFT_OPTIONS[@]}" --product ActionTapeStudio
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
EXECUTABLE="${BIN_DIR}/ActionTapeStudio"

if [[ ! -x "${EXECUTABLE}" ]]; then
  echo "Expected executable was not produced: ${EXECUTABLE}" >&2
  exit 1
fi

mkdir -p -- "${STAGING_APP}/Contents/MacOS" "${STAGING_APP}/Contents/Resources"
install -m 0755 "${EXECUTABLE}" "${STAGING_APP}/Contents/MacOS/ActionTape"
install -m 0644 "${SCRIPT_DIR}/ActionTape.Info.plist" "${STAGING_APP}/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${STAGING_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${STAGING_APP}/Contents/Info.plist"

ICON_SOURCE="${PROJECT_DIR}/Sources/ActionTapeStudio/Resources/AppIcon.png"
if [[ ! -f "${ICON_SOURCE}" ]]; then
  echo "Missing checked-in app icon: ${ICON_SOURCE}" >&2
  exit 1
fi

bash "${SCRIPT_DIR}/create-app-icon.sh" "${ICON_SOURCE}" "${STAGING_APP}/Contents/Resources/ActionTape.icns"

# SwiftPM's generated Bundle.module accessor appends this name to
# Bundle.main.bundleURL (the .app root), not Bundle.main.resourceURL. Without
# the relative link it can silently use an absolute .build fallback on the
# developer's Mac and crash after the app is moved to another machine.
BUNDLE_NAME="ActionTape_ActionTapeStudio.bundle"
RESOURCE_BUNDLE="${BIN_DIR}/${BUNDLE_NAME}"
if [[ ! -f "${RESOURCE_BUNDLE}/AppIcon.png" ]]; then
  echo "Missing SwiftPM resource bundle: ${RESOURCE_BUNDLE}" >&2
  exit 1
fi
/usr/bin/ditto "${RESOURCE_BUNDLE}" "${STAGING_APP}/Contents/Resources/${BUNDLE_NAME}"
ln -s "Contents/Resources/${BUNDLE_NAME}" "${STAGING_APP}/${BUNDLE_NAME}"

LICENSE_DIR="${STAGING_APP}/Contents/Resources/Licenses"
mkdir -p -- "${LICENSE_DIR}"
install -m 0644 "${PROJECT_DIR}/LICENSE" "${LICENSE_DIR}/ActionTape-LICENSE.txt"
install -m 0644 "${PROJECT_DIR}/Vendor/Yams/LICENSE" "${LICENSE_DIR}/Yams-LICENSE.txt"
install -m 0644 "${PROJECT_DIR}/Vendor/Yams/NOTICE.md" "${LICENSE_DIR}/ThirdParty-NOTICE.md"

swift "${SCRIPT_DIR}/verify-app.swift" "${STAGING_APP}"

if [[ -e "${FINAL_APP}" || -L "${FINAL_APP}" ]]; then
  BACKUP_ROOT="$(mktemp -d "${OUTPUT_DIR}/ActionTape-previous.XXXXXX")"
  mv -- "${FINAL_APP}" "${BACKUP_ROOT}/ActionTape.app"
  echo "Preserved the previous bundle at ${BACKUP_ROOT}/ActionTape.app"
fi
mv -- "${STAGING_APP}" "${FINAL_APP}"

echo "Created ${FINAL_APP}"
echo "Development bundle only: no Developer ID signature or notarization was added."
